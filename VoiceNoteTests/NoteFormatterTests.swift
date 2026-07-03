import XCTest
@testable import VoiceNote

/// `NoteFormatter` 是無 IO 的純函式邏輯，直接以字串斷言驗證。
final class NoteFormatterTests: XCTestCase {

    func test_fileName_isYYYYMMDD() {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        XCTAssertEqual(NoteFormatter.fileName(for: date), "2026-05-02.md")
    }

    func test_header_isH1WithDate() {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 0, minute: 0, second: 0)
        XCTAssertEqual(NoteFormatter.header(for: date), "# 2026-05-02\n")
    }

    func test_entry_formatsTimeHeadingAndBody() {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        XCTAssertEqual(
            NoteFormatter.entry(transcript: "測試一二三", at: date),
            "\n## 14:30:12\n\n測試一二三\n"
        )
    }

    // MARK: - replacingLastOccurrence

    func test_replacingLastOccurrence_replacesOnlyLastMatch() {
        let text = "早安 早安 晚安"
        let result = NoteFormatter.replacingLastOccurrence(of: "早安", with: "午安", in: text)
        XCTAssertEqual(result, "早安 午安 晚安")
    }

    func test_replacingLastOccurrence_returnsNilWhenNotFound() {
        XCTAssertNil(NoteFormatter.replacingLastOccurrence(of: "不存在", with: "X", in: "一些內容"))
    }

    func test_replacingLastOccurrence_handlesUnicode() {
        let text = "會議記錄\n重點：語音轉錄\n語音轉錄"
        let result = NoteFormatter.replacingLastOccurrence(of: "語音轉錄", with: "語音辨識", in: text)
        XCTAssertEqual(result, "會議記錄\n重點：語音轉錄\n語音辨識")
    }

    // MARK: - Helpers

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
