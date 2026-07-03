import XCTest
@testable import VoiceNote

@MainActor
final class AppStateTests: XCTestCase {

    /// Each test gets a fresh AppState backed by an isolated UserDefaults suite,
    /// so tests no longer pollute each other via the shared singleton.
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "AppStateTests-\(UUID().uuidString)")!
        return AppState(settings: SettingsStore(defaults: defaults))
    }

    func test_setError_setsStateAndLastError() {
        let s = makeState()

        s.setError("boom")

        XCTAssertEqual(s.lastError, "boom")
        guard case .error(let msg) = s.state else {
            return XCTFail("expected .error state")
        }
        XCTAssertEqual(msg, "boom")
    }

    func test_noteSoftFailure_setsLastErrorButKeepsStateIdle() {
        let s = makeState()
        s.state = .recording(startedAt: Date())

        s.noteSoftFailure("transient")

        XCTAssertEqual(s.lastError, "transient")
        XCTAssertEqual(s.state, .idle)
    }

    func test_clearTransientError_resetsErrorStateToIdle() {
        let s = makeState()
        s.setError("oops")
        XCTAssertNotNil(s.lastError)

        s.clearTransientError()

        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.state, .idle)
    }

    func test_clearTransientError_doesNotMutateNonErrorState() {
        let s = makeState()
        let started = Date()
        s.state = .recording(startedAt: started)
        s.lastError = "leftover"

        s.clearTransientError()

        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.state, .recording(startedAt: started))
    }

    func test_recorderState_isBusy_recognisesActiveStates() {
        XCTAssertTrue(RecorderState.recording(startedAt: Date()).isBusy)
        XCTAssertTrue(RecorderState.transcribing.isBusy)
        XCTAssertTrue(RecorderState.downloadingModel(progress: 0.5).isBusy)

        XCTAssertFalse(RecorderState.idle.isBusy)
        XCTAssertFalse(RecorderState.error("x").isBusy)
    }

    func test_recorderState_equality_treatsErrorsByMessage() {
        XCTAssertEqual(RecorderState.error("x"), RecorderState.error("x"))
        XCTAssertNotEqual(RecorderState.error("x"), RecorderState.error("y"))
    }

    // MARK: - 設定寫入會透傳到 SettingsStore

    func test_setters_updatePublishedProperties() {
        let s = makeState()

        s.updateModelChoice("openai_whisper-small")
        s.setAutoProofread(true)
        s.setChineseVariant(.simplified)
        s.setPasteAtCursor(false)
        s.setDecodingTopK(9)
        s.setDecodingTemperature(0.4)
        s.setDecodingFallbackCount(2)

        XCTAssertEqual(s.selectedModel, "openai_whisper-small")
        XCTAssertTrue(s.autoProofread)
        XCTAssertEqual(s.chineseVariant, .simplified)
        XCTAssertFalse(s.pasteAtCursor)
        XCTAssertEqual(s.decodingTopK, 9)
        XCTAssertEqual(s.decodingTemperature, 0.4)
        XCTAssertEqual(s.decodingFallbackCount, 2)
    }

    func test_settings_persistToInjectedStore() {
        let defaults = UserDefaults(suiteName: "AppStateTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)

        let s = AppState(settings: store)
        s.setChineseVariant(.simplified)
        s.updateModelChoice("openai_whisper-small")

        // A fresh AppState over the same store should observe the persisted values.
        let reloaded = AppState(settings: store)
        XCTAssertEqual(reloaded.chineseVariant, .simplified)
        XCTAssertEqual(reloaded.selectedModel, "openai_whisper-small")
    }
}
