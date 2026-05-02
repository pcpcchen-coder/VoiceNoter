import SwiftUI
import AppKit

@main
struct VoiceNoteApp: App {
    @StateObject private var state: AppState
    @StateObject private var coordinator: RecordingCoordinator

    @MainActor
    init() {
        Paths.ensureDirectoriesExist()
        Paths.bootstrapGlossaryIfNeeded()
        let appState = AppState.shared
        _state = StateObject(wrappedValue: appState)
        _coordinator = StateObject(wrappedValue: RecordingCoordinator(state: appState))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            StatusIcon(state: state.state, micDenied: state.micPermission == .denied)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView().environmentObject(state)
        }
    }
}

/// Wires hotkey events to AudioRecorder → TranscriptionService → NoteWriter,
/// and reflects progress back into AppState. Single instance owned by the App.
@MainActor
final class RecordingCoordinator: ObservableObject {
    private let state: AppState
    private let recorder = AudioRecorder()
    private let transcription = TranscriptionService()
    private var hotkey: HotkeyManager!
    private var maxDurationGuard: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        self.hotkey = HotkeyManager(
            onPress: { [weak self] in self?.handlePress() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
        self.hotkey.register()

        Task { await self.warmupModel() }
    }

    // MARK: - Warmup

    private func warmupModel() async {
        let modelName = state.selectedModel
        state.state = .downloadingModel(progress: 0)
        do {
            try await transcription.warmup(modelName: modelName) { [weak self] progress in
                guard let self else { return }
                if progress >= 1.0 {
                    self.state.state = .idle
                } else {
                    self.state.state = .downloadingModel(progress: progress)
                }
            }
            state.state = .idle
            Log.app.info("Warmup completed for model \(modelName, privacy: .public)")
        } catch {
            state.setError("模型初始化失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - Hotkey handlers

    private func handlePress() {
        // Block while busy or downloading.
        switch state.state {
        case .recording, .transcribing, .downloadingModel:
            return
        default:
            break
        }

        // First-press permission flow: request mic access if undetermined; abort otherwise.
        switch state.micPermission {
        case .denied:
            state.setError("麥克風權限未授予")
            return
        case .undetermined:
            Task { [weak self] in
                guard let self else { return }
                let granted = await PermissionHelper.requestMicrophoneAccess()
                self.state.refreshMicPermission()
                if granted {
                    self.startRecordingNow()
                } else {
                    self.state.setError("麥克風權限未授予")
                }
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
            state.setError(error.localizedDescription)
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
            state.setError(error.localizedDescription)
            return
        }

        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            let prompt = Paths.readGlossaryAsPrompt()
            let text = try await transcription.transcribe(audioURL: audioURL, prompt: prompt)
            state.lastTranscript = text
            NoteWriter.copyToPasteboard(text)
            try NoteWriter.append(transcript: text)
            state.state = .idle
            state.lastError = nil
        } catch {
            state.setError("轉錄失敗：\(error.localizedDescription)")
        }
    }
}
