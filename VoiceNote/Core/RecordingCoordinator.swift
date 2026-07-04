import Foundation
import Combine

/// Wires hotkey events to AudioRecording → Transcribing → NoteStoring, and reflects
/// progress back into AppState. All collaborators are injected so the flow is testable
/// without touching a real microphone, model, network, or filesystem.
///
/// Construction is side-effect free; `activate()` mounts the global hotkey and warms up
/// the model. Tests build the coordinator and drive `handlePress()` / `handleRelease()`
/// directly, skipping `activate()`.
@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published var modelLoadFailed: Bool = false

    private let state: AppState
    private let settings: SettingsStore
    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let noteStore: NoteStoring
    private let rewriter: TextRewriting
    private let deliverer: TranscriptDelivering
    private let glossary: GlossaryStore
    private let pipeline: PostTranscriptionPipeline

    private var hotkey: HotkeyManager?
    private var warmupTask: Task<Void, Never>?
    private var maxDurationGuard: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var isActivated = false

    init(
        state: AppState,
        settings: SettingsStore,
        recorder: AudioRecording,
        transcriber: Transcribing,
        noteStore: NoteStoring,
        rewriter: TextRewriting,
        deliverer: TranscriptDelivering,
        glossary: GlossaryStore
    ) {
        self.state = state
        self.settings = settings
        self.recorder = recorder
        self.transcriber = transcriber
        self.noteStore = noteStore
        self.rewriter = rewriter
        self.deliverer = deliverer
        self.glossary = glossary
        self.pipeline = PostTranscriptionPipeline(rewriter: rewriter, noteStore: noteStore, state: state)
    }

    /// Side effects that should only run in the real app: register the global hotkey and
    /// kick off model warmup. Idempotent.
    func activate() {
        guard !isActivated else { return }
        isActivated = true

        let hotkey = HotkeyManager(
            onPress: { [weak self] in self?.handlePress() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
        hotkey.register()
        self.hotkey = hotkey

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

    // MARK: - Hotkey handlers (internal for tests)

    func handlePress() {
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

    func handleRelease() {
        guard case .recording = state.state else { return }
        maxDurationGuard?.cancel()
        maxDurationGuard = nil

        state.state = .transcribing
        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            await self?.runTranscription()
        }
    }

    /// Test helper: await the in-flight transcription task.
    func waitForPendingWork() async {
        await transcribeTask?.value
    }

    func runTranscription() async {
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
            let now = Date()
            let decoding = DecodingSettings(settings: settings, prompt: glossary.prompt())
            let text = try await transcriber.transcribe(audioURL: audioURL, settings: decoding)
            state.lastTranscript = text

            // Deliver the original transcript to the cursor (low latency); the note may be
            // superseded by the proofread version below. See README's B5 tradeoff note.
            deliverer.deliver(text, pasteAtCursor: state.pasteAtCursor)

            let isOrganizeCommand = PostTranscriptionPipeline.detectOrganizeCommand(text)
            // The "organize" trigger utterance is a command, not a note — don't append it.
            if !isOrganizeCommand {
                try noteStore.append(transcript: text, at: now)
            }

            // Core flow is done; go idle. Post-processing sets its own info/error messages.
            state.state = .idle

            if isOrganizeCommand {
                await pipeline.organize(now: now)
            } else {
                await pipeline.proofread(original: text, enabled: state.autoProofread, now: now)
            }
        } catch {
            state.noteSoftFailure("上次轉錄失敗：\(error.localizedDescription)")
        }
    }
}
