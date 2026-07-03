import SwiftUI
import AppKit

@main
struct VoiceNoteApp: App {
    @StateObject private var state: AppState
    @StateObject private var coordinator: RecordingCoordinator

    @MainActor
    init() {
        Paths.ensureDirectoriesExist()
        GlossaryStore().bootstrapIfNeeded()
        migrateLegacyToken(defaults: .standard, into: KeychainCredentialStore())
        let appState = AppState.shared
        _state = StateObject(wrappedValue: appState)
        _coordinator = StateObject(wrappedValue: RecordingCoordinator(state: appState))
        PermissionHelper.requestAccessibilityIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(coordinator)
        } label: {
            StatusIcon(state: state.state, micDenied: state.micPermission == .denied)
        }
        .menuBarExtraStyle(.menu)

        Window("VoiceNote 設定", id: "settings") {
            SettingsView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Wires hotkey events to AudioRecorder → WhisperKitTranscriber → NoteStore,
/// and reflects progress back into AppState. Single instance owned by the App.
@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published var modelLoadFailed: Bool = false

    private let state: AppState
    private let recorder = AudioRecorder()
    private let transcriber: Transcribing
    private let noteStore: NoteStoring = FileNoteStore()
    private let glossary = GlossaryStore()
    private let rewriter: TextRewriting
    private var hotkey: HotkeyManager!
    private var warmupTask: Task<Void, Never>?
    private var maxDurationGuard: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        self.transcriber = WhisperKitTranscriber(settings: state.settings)
        self.rewriter = OpenAIRewriter(credentials: KeychainCredentialStore())
        self.hotkey = HotkeyManager(
            onPress: { [weak self] in self?.handlePress() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
        self.hotkey.register()
        scheduleWarmup()
    }

    // MARK: - Warmup

    func retryWarmup() {
        scheduleWarmup()
    }

    private func scheduleWarmup() {
        warmupTask?.cancel()
        warmupTask = Task { @MainActor [weak self] in
            await self?.warmupModel()
        }
    }

    private func warmupModel() async {
        let modelName = state.selectedModel
        modelLoadFailed = false
        state.lastError = nil
        state.state = .downloadingModel(progress: 0)
        do {
            try await transcriber.warmup(
                modelName: modelName,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    if progress >= 1.0 {
                        self.state.state = .idle
                    } else {
                        self.state.state = .downloadingModel(progress: progress)
                    }
                },
                onLoadingStarted: { [weak self] in
                    self?.state.state = .loadingModel
                }
            )
            state.state = .idle
            state.lastError = nil
            Log.app.info("Warmup completed for model \(modelName, privacy: .public)")
        } catch is CancellationError {
            // Superseded by another warmup; do nothing.
            return
        } catch {
            // Use a soft failure so the icon stays in the normal "mic" look — the spec
            // reserves the gray icon for a denied microphone permission. The retry
            // button is gated by `modelLoadFailed`, and `handlePress()` blocks recording
            // while `transcriber.isReady == false`.
            modelLoadFailed = true
            state.noteSoftFailure("模型初始化失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - Hotkey handlers

    private func handlePress() {
        // Block while busy or downloading.
        switch state.state {
        case .recording, .transcribing, .downloadingModel, .loadingModel:
            return
        default:
            break
        }

        // Model not ready yet — fail fast so the user isn't surprised at transcribe time.
        if !transcriber.isReady {
            if modelLoadFailed {
                state.noteSoftFailure("模型尚未載入，請點擊「重試模型載入」")
            } else {
                state.noteSoftFailure("模型尚在載入中，請稍候…")
            }
            return
        }

        // First-press permission flow: request mic access if undetermined; abort otherwise.
        switch state.micPermission {
        case .denied:
            state.noteSoftFailure("麥克風權限未授予")
            return
        case .undetermined:
            // Trigger system permission prompt; do NOT auto-record afterwards because
            // the user has likely already released the hotkey while answering the dialog.
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await PermissionHelper.requestMicrophoneAccess()
                self.state.refreshMicPermission()
            }
            return
        case .authorized:
            break
        }

        startRecordingNow()
    }

    private func startRecordingNow() {
        state.clearTransientError()
        do {
            try recorder.start()
            state.state = .recording(startedAt: Date())

            // Hard cap the recording at maxDurationSeconds.
            maxDurationGuard?.cancel()
            maxDurationGuard = Task { [weak self] in
                let nanos = UInt64(AudioRecorder.maxDurationSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                self?.handleRelease()
            }
        } catch {
            state.noteSoftFailure("錄音失敗：\(error.localizedDescription)")
        }
    }

    private func handleRelease() {
        guard case .recording = state.state else { return }
        maxDurationGuard?.cancel()
        maxDurationGuard = nil

        state.state = .transcribing
        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            await self?.runTranscription()
        }
    }

    private func runTranscription() async {
        let audioURL: URL
        do {
            audioURL = try await recorder.stop()
        } catch AudioRecorderError.tooShort {
            Log.app.info("Recording too short, ignored")
            state.state = .idle
            return
        } catch {
            state.noteSoftFailure("錄音停止失敗：\(error.localizedDescription)")
            return
        }

        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            let decoding = DecodingSettings(settings: state.settings, prompt: glossary.prompt())
            let text = try await transcriber.transcribe(audioURL: audioURL, settings: decoding)
            state.lastTranscript = text
            if state.pasteAtCursor {
                TranscriptDeliverer.pasteAtCursor(text)
            } else {
                TranscriptDeliverer.copyToPasteboard(text)
            }
            try noteStore.append(transcript: text, at: Date())

            if state.autoProofread {
                do {
                    let proofread = try await rewriter.rewrite(text)
                    let noteURL = noteStore.todayNoteURL(now: Date())
                    if var fileContent = try? String(contentsOf: noteURL, encoding: .utf8) {
                        if let range = fileContent.range(of: text, options: .backwards) {
                            fileContent.replaceSubrange(range, with: proofread)
                            try? fileContent.write(to: noteURL, atomically: true, encoding: .utf8)
                        }
                    }
                    self.state.noteSoftFailure("語音已自動校稿")
                } catch {
                    self.state.noteSoftFailure("AI 校稿失敗：\(error.localizedDescription)")
                }
            }
            
            if text.contains("幫我整理") || text.contains("請整理") {
                let noteURL = noteStore.todayNoteURL(now: Date())
                if let original = try? String(contentsOf: noteURL), !original.isEmpty {
                    Task { @MainActor in
                        do {
                            let rewritten = try await rewriter.rewrite(original)
                            try? rewritten.write(to: noteURL, atomically: true, encoding: .utf8)
                            self.state.noteSoftFailure("筆記內容已由 AI 整理")
                        } catch {
                            self.state.noteSoftFailure("AI 整理失敗：\(error.localizedDescription)")
                        }
                    }
                }
            }
            
            state.state = .idle
            state.lastError = nil
        } catch {
            state.noteSoftFailure("上次轉錄失敗：\(error.localizedDescription)")
        }
    }
}
