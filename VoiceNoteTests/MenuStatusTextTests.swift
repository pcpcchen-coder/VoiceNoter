import XCTest
@testable import VoiceNote

final class MenuStatusTextTests: XCTestCase {

    func test_idle_showsHotkeyDescription() {
        XCTAssertEqual(
            MenuStatusText.line(state: .idle, hotkeyDescription: "⌥Space"),
            "待機中 · 熱鍵 ⌥Space"
        )
    }

    func test_recording() {
        XCTAssertEqual(
            MenuStatusText.line(state: .recording(startedAt: Date()), hotkeyDescription: "⌥Space"),
            "錄音中…"
        )
    }

    func test_transcribing() {
        XCTAssertEqual(MenuStatusText.line(state: .transcribing, hotkeyDescription: "x"), "轉錄中…")
    }

    func test_error() {
        XCTAssertEqual(MenuStatusText.line(state: .error("boom"), hotkeyDescription: "x"), "發生錯誤")
    }

    func test_downloadingModel_showsPercent() {
        XCTAssertEqual(
            MenuStatusText.line(state: .downloadingModel(progress: 0.42), hotkeyDescription: "x"),
            "下載模型中 42%"
        )
    }

    func test_loadingModel() {
        XCTAssertEqual(
            MenuStatusText.line(state: .loadingModel, hotkeyDescription: "x"),
            "載入模型中（首次可能需要數分鐘）…"
        )
    }
}
