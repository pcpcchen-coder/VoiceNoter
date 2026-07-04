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
    private let state: AppState
    private let settings: SettingsStore
    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let noteStore: NoteStoring
    private let rewriter: TextRewriting
    private let deliverer: TranscriptDelivering
    private let glossary: GlossaryStore
    private let isAccessibilityGranted: () -> Bool
    private let pipeline: PostTranscriptionPipeline

    private var hotkey: HotkeyManager?
    private var warmupTask: Task<Void, Never>?
    private var maxDurationGuard: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isActivated = false

    init(
        state: AppState,
        settings: SettingsStore,
        recorder: AudioRecording,
        transcriber: Transcribing,
        noteStore: NoteStoring,
        rewriter: TextRewriting,
        deliverer: TranscriptDelivering,
        glossary: GlossaryStore,
        isAccessibilityGranted: @escaping () -> Bool = { PermissionHelper.isAccessibilityGranted() }
    ) {
        self.state = state
        self.settings = settings
        self.recorder = recorder
        self.transcriber = transcriber
        self.noteStore = noteStore
        self.rewriter = rewriter
        self.deliverer = deliverer
        self.glossary = glossary
        self.isAccessibilityGranted = isAccessibilityGranted
        self.pipeline = PostTranscriptionPipeline(rewriter: rewriter, noteStore: noteStore, state: state)

        // Reload the model whenever the user picks a different one (no app restart).
        // dropFirst() skips the initial value so construction stays side-effect free.
        state.$selectedModel
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newModel in
                self?.scheduleWarmup(modelName: newModel)
            }
            .store(in: &cancellables)
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

        scheduleWarmup(modelName: state.selectedModel)
    }

    // MARK: - Warmup

    func retryWarmup() {
        scheduleWarmup(modelName: state.selectedModel)
    }

    /// Test helper: await the in-flight warmup task.
    func waitForWarmup() async {
        await warmupTask?.value
    }

    private func scheduleWarmup(modelName: String) {
        warmupTask?.cancel()
        warmupTask = Task { @MainActor [weak self] in
            await self?.warmupModel(modelName: modelName)
        }
    }

    private func warmupModel(modelName: String) async {
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
            // Model load failure is a hard error → `.error` state (single source of truth).
            // The menu's retry button is driven by `case .error`, and `handlePress()` blocks
            // recording while in `.error`.
            state.setError("模型初始化失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - Hotkey handlers (internal for tests)

    func handlePress() {
        switch state.state {
        case .recording, .transcribing:
            return
        case .downloadingModel, .loadingModel:
            // Reload / warmup in progress — tell the user to wait, keep the state intact.
            state.flashError("模型尚在載入中，請稍候…")
            return
        case .error:
            // Model failed to load; the menu already shows the error + retry button.
            return
        case .idle:
            break
        }

        // Defensive: idle but not ready yet.
        if !transcriber.isReady {
            state.flashError("模型尚在載入中，請稍候…")
            return
        }

        // First-press permission flow: request mic access if undetermined; abort otherwise.
        switch state.micPermission {
        case .denied:
            state.flashError("麥克風權限未授予")
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
            // Cursor paste needs Accessibility (B8): fall back to clipboard-only + a hint.
            let wantsPaste = state.pasteAtCursor
            let canPaste = wantsPaste && isAccessibilityGranted()
            deliverer.deliver(text, pasteAtCursor: canPaste)
            if wantsPaste && !canPaste {
                state.noteInfo("已複製到剪貼簿（游標輸入需在「系統設定 → 輔助使用」開啟權限）")
            }

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
