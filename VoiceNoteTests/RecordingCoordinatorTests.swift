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
            glossary: glossary
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

    func test_press_whenModelLoadFailed_showsRetryMessage() throws {
        let rig = try makeRig(transcriberReady: false)
        rig.coordinator.modelLoadFailed = true

        rig.coordinator.handlePress()

        XCTAssertEqual(rig.state.lastError, "模型尚未載入，請點擊「重試模型載入」")
        XCTAssertEqual(rig.recorder.startCallCount, 0)
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
}
