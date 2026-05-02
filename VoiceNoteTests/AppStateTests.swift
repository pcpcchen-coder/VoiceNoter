import XCTest
@testable import VoiceNote

@MainActor
final class AppStateTests: XCTestCase {

    func test_setError_setsStateAndLastError() {
        let s = AppState.shared
        s.state = .idle
        s.lastError = nil

        s.setError("boom")

        XCTAssertEqual(s.lastError, "boom")
        guard case .error(let msg) = s.state else {
            return XCTFail("expected .error state")
        }
        XCTAssertEqual(msg, "boom")
    }

    func test_noteSoftFailure_setsLastErrorButKeepsStateIdle() {
        let s = AppState.shared
        s.state = .recording(startedAt: Date())
        s.lastError = nil

        s.noteSoftFailure("transient")

        XCTAssertEqual(s.lastError, "transient")
        XCTAssertEqual(s.state, .idle)
    }

    func test_clearTransientError_resetsErrorStateToIdle() {
        let s = AppState.shared
        s.setError("oops")
        XCTAssertNotNil(s.lastError)

        s.clearTransientError()

        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.state, .idle)
    }

    func test_clearTransientError_doesNotMutateNonErrorState() {
        let s = AppState.shared
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
}
