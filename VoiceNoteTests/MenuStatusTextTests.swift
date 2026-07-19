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

    // MARK: - menuBarProgressText (compact % shown on the menu-bar label)

    func test_menuBarProgressText_downloading_returnsPercent() {
        XCTAssertEqual(MenuStatusText.menuBarProgressText(state: .downloadingModel(progress: 0.42)), "42%")
    }

    func test_menuBarProgressText_zeroAndFull() {
        XCTAssertEqual(MenuStatusText.menuBarProgressText(state: .downloadingModel(progress: 0)), "0%")
        XCTAssertEqual(MenuStatusText.menuBarProgressText(state: .downloadingModel(progress: 1.0)), "100%")
    }

    func test_menuBarProgressText_nonDownloadingStates_returnNil() {
        XCTAssertNil(MenuStatusText.menuBarProgressText(state: .idle))
        XCTAssertNil(MenuStatusText.menuBarProgressText(state: .loadingModel))
        XCTAssertNil(MenuStatusText.menuBarProgressText(state: .transcribing))
        XCTAssertNil(MenuStatusText.menuBarProgressText(state: .recording(startedAt: Date())))
        XCTAssertNil(MenuStatusText.menuBarProgressText(state: .error("x")))
    }
}
