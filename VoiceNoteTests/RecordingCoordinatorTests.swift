import XCTest
@testable import VoiceNote

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rc-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Test rig

    private struct Rig {
        let coordinator: RecordingCoordinator
        let state: AppState
        let recorder: MockAudioRecorder
        let transcriber: MockTranscriber
        let noteStore: MockNoteStore
        let rewriter: MockRewriter
        let deliverer: MockDeliverer
    }

    private func makeRig(
        micPermission: MicrophonePermissionStatus = .authorized,
        pasteAtCursor: Bool = true,
        autoProofread: Bool = false,
        transcriberReady: Bool = true,
        accessibilityGranted: Bool = true,
        glossaryTerms: String = "EMS\nPCS\n"
    ) throws -> Rig {
        let defaults = UserDefaults(suiteName: "RC-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let state = AppState(settings: settings)
        state.micPermission = micPermission
        state.setPasteAtCursor(pasteAtCursor)
        state.setAutoProofread(autoProofread)

        let recorder = MockAudioRecorder()
        let transcriber = MockTranscriber()
        transcriber.isReadyValue = transcriberReady
        let noteStore = MockNoteStore()
        let rewriter = MockRewriter()
        let deliverer = MockDeliverer()

        let glossaryFile = tempDir.appendingPathComponent("glossary-\(UUID().uuidString).txt")
        try glossaryTerms.write(to: glossaryFile, atomically: true, encoding: .utf8)
        let glossary = GlossaryStore(fileURL: glossaryFile, defaultSource: nil)

        let coordinator = RecordingCoordinator(
            state: state,
            settings: settings,
            recorder: recorder,
            transcriber: transcriber,
            noteStore: noteStore,
            rewriter: rewriter,
            deliverer: deliverer,
            glossary: glossary,
            isAccessibilityGranted: { accessibilityGranted }
        )
        return Rig(coordinator: coordinator, state: state, recorder: recorder,
                   transcriber: transcriber, noteStore: noteStore, rewriter: rewriter,
                   deliverer: deliverer)
    }

    private func isRecording(_ state: RecorderState) -> Bool {
        if case .recording = state { return true }
        return false
    }

    // MARK: - press

    func test_press_whenModelNotReady_showsWaitMessage_andDoesNotStartRecorder() throws {
        let rig = try makeRig(transcriberReady: false)

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.state.lastError, "模型尚在載入中，請稍候…")
        XCTAssertEqual(rig.recorder.startCallCount, 0)
    }

    func test_press_whenModelError_isBlocked_withoutClearingError() throws {
        let rig = try makeRig(transcriberReady: false)
        rig.state.setError("模型初始化失敗")

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.recorder.startCallCount, 0)
        guard case .error = rig.state.state else {
            return XCTFail(".error state must persist across a press")
        }
    }

    func test_press_duringModelReload_isBlockedWithMessage() throws {
        let rig = try makeRig()
        rig.state.state = .downloadingModel(progress: 0.3)

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.recorder.startCallCount, 0)
        XCTAssertEqual(rig.state.lastError, "模型尚在載入中，請稍候…")
        XCTAssertEqual(rig.state.state, .downloadingModel(progress: 0.3))
    }

    func test_press_whenMicDenied_showsPermissionMessage() throws {
        let rig = try makeRig(micPermission: .denied)

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.state.lastError, "麥克風權限未授予")
        XCTAssertEqual(rig.recorder.startCallCount, 0)
    }

    func test_press_whenAuthorized_startsRecorder_andEntersRecordingState() throws {
        let rig = try makeRig()

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.recorder.startCallCount, 1)
        XCTAssertTrue(isRecording(rig.state.state))
    }

    func test_press_whileBusy_isIgnored() throws {
        let busyStates: [RecorderState] = [
            .recording(startedAt: Date()),
            .transcribing,
            .downloadingModel(progress: 0.5),
            .loadingModel,
        ]
        for busy in busyStates {
            let rig = try makeRig()
            rig.state.state = busy

            rig.coordinator.handlePress()

            XCTAssertEqual(rig.recorder.startCallCount, 0, "should ignore press while \(busy)")
        }
    }

    // MARK: - release

    func test_release_transcribes_appendsNote_andDelivers() async throws {
        let rig = try makeRig(pasteAtCursor: true, glossaryTerms: "EMS\nPCS\n")
        rig.transcriber.transcribeResult = .success("測試逐字稿")

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertEqual(rig.transcriber.transcribeCalls.count, 1)
        XCTAssertEqual(rig.transcriber.transcribeCalls.first?.settings.prompt, "EMS, PCS")
        XCTAssertEqual(rig.noteStore.appendedTranscripts, ["測試逐字稿"])
        XCTAssertEqual(rig.deliverer.deliveredText, "測試逐字稿")
        XCTAssertEqual(rig.deliverer.deliveredWithPaste, true)
        XCTAssertEqual(rig.state.lastTranscript, "測試逐字稿")
        XCTAssertEqual(rig.state.state, .idle)
    }

    func test_release_deliveryRespectsPasteAtCursorSetting() async throws {
        for paste in [true, false] {
            let rig = try makeRig(pasteAtCursor: paste)
            rig.coordinator.handlePress()
            rig.coordinator.handleRelease()
            await rig.coordinator.waitForPendingWork()

            XCTAssertEqual(rig.deliverer.deliveredWithPaste, paste)
        }
    }

    /// B8: paste-at-cursor without Accessibility falls back to clipboard-only + a hint.
    func test_release_pasteWithoutAccessibility_fallsBackToClipboard_withHint() async throws {
        let rig = try makeRig(pasteAtCursor: true, accessibilityGranted: false)
        rig.transcriber.transcribeResult = .success("內容")

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertEqual(rig.deliverer.deliveredWithPaste, false)
        XCTAssertEqual(rig.deliverer.deliveredText, "內容")
        XCTAssertNotNil(rig.state.infoMessage)
    }

    func test_release_tooShortRecording_returnsToIdle_writesNothing() async throws {
        let rig = try makeRig()
        rig.recorder.stopResult = .failure(AudioRecorderError.tooShort)

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertEqual(rig.state.state, .idle)
        XCTAssertTrue(rig.noteStore.appendedTranscripts.isEmpty)
        XCTAssertNil(rig.deliverer.deliveredText)
        XCTAssertEqual(rig.transcriber.transcribeCalls.count, 0)
    }

    func test_release_transcriptionFailure_setsLastError() async throws {
        let rig = try makeRig()
        rig.transcriber.transcribeResult = .failure(TranscriptionError.underlying("boom"))

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertNotNil(rig.state.lastError)
        XCTAssertTrue(rig.state.lastError?.hasPrefix("上次轉錄失敗") == true)
        XCTAssertTrue(rig.noteStore.appendedTranscripts.isEmpty)
    }

    func test_release_withoutRecording_isNoop() async throws {
        let rig = try makeRig()
        rig.state.state = .idle

        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertEqual(rig.state.state, .idle)
        XCTAssertEqual(rig.transcriber.transcribeCalls.count, 0)
        XCTAssertEqual(rig.recorder.stopCallCount, 0)
    }

    // MARK: - Step 11 regressions (B1/B2/B3)

    func test_newRecording_clearsInfoMessageAndLastError() throws {
        let rig = try makeRig()
        rig.state.lastError = "舊錯誤"
        rig.state.infoMessage = "舊資訊"

        rig.coordinator.handlePress()

        XCTAssertNil(rig.state.lastError)
        XCTAssertNil(rig.state.infoMessage)
        XCTAssertTrue(isRecording(rig.state.state))
    }

    /// B1 + B2: proofread success shows a gray info message (not a red error) and it
    /// survives the run completing (no tail clears it).
    func test_release_proofreadSuccess_setsInfoMessage_notLastError() async throws {
        let rig = try makeRig(autoProofread: true)
        rig.transcriber.transcribeResult = .success("原始逐字稿")
        rig.rewriter.result = .success("校稿後")

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertEqual(rig.state.infoMessage, "已自動校稿")
        XCTAssertNil(rig.state.lastError)
        XCTAssertEqual(rig.noteStore.replaceCalls.first?.replacement, "校稿後")
        XCTAssertEqual(rig.state.state, .idle)
    }

    /// B3: an organize command appends a summary section and never overwrites the note;
    /// the trigger utterance itself is not written.
    func test_release_organizeCommand_appendsSummary_notTrigger() async throws {
        let rig = try makeRig()
        rig.transcriber.transcribeResult = .success("幫我整理今天的筆記")
        rig.noteStore.readResult = .success("# 2026-05-02\n\n## 09:00:00\n\n既有內容\n")
        rig.rewriter.result = .success("整理摘要")

        rig.coordinator.handlePress()
        rig.coordinator.handleRelease()
        await rig.coordinator.waitForPendingWork()

        XCTAssertTrue(rig.noteStore.appendedTranscripts.isEmpty, "trigger utterance must not be appended")
        XCTAssertEqual(rig.noteStore.appendedSections.count, 1)
        XCTAssertEqual(rig.noteStore.appendedSections.first?.body, "整理摘要")
        XCTAssertEqual(rig.state.infoMessage, "筆記已由 AI 整理")
    }

    // MARK: - Step 12: warmup / model reload

    func test_warmupFailure_entersErrorState() async throws {
        let rig = try makeRig(transcriberReady: false)
        rig.transcriber.warmupError = TranscriptionError.underlying("boom")

        rig.coordinator.retryWarmup()
        await rig.coordinator.waitForWarmup()

        guard case .error = rig.state.state else {
            return XCTFail("warmup failure should enter .error")
        }
        XCTAssertNotNil(rig.state.lastError)
    }

    func test_retryWarmup_fromErrorState_recovers() async throws {
        let rig = try makeRig(transcriberReady: false)
        rig.transcriber.warmupError = TranscriptionError.underlying("boom")
        rig.coordinator.retryWarmup()
        await rig.coordinator.waitForWarmup()
        guard case .error = rig.state.state else {
            return XCTFail("expected .error first")
        }

        rig.transcriber.warmupError = nil
        rig.coordinator.retryWarmup()
        await rig.coordinator.waitForWarmup()

        XCTAssertEqual(rig.state.state, .idle)
        XCTAssertNil(rig.state.lastError)
        XCTAssertTrue(rig.transcriber.isReady)
    }

    func test_modelChange_restartsWarmup_withNewModelName() async throws {
        let rig = try makeRig()

        rig.state.updateModelChoice("openai_whisper-small")
        await rig.coordinator.waitForWarmup()

        XCTAssertEqual(rig.transcriber.warmupCalls.last, "openai_whisper-small")
    }
}
