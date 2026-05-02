import XCTest
@testable import VoiceNote

final class NoteWriterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_todayNoteURL_returnsYYYYMMDDFile() {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        let url = NoteWriter.todayNoteURL(now: date, directory: tempDir)
        XCTAssertEqual(url.lastPathComponent, "2026-05-02.md")
        XCTAssertEqual(url.deletingLastPathComponent().path, tempDir.path)
    }

    func test_append_createsFileWithHeaderAndEntry() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        let url = try NoteWriter.append(transcript: "測試一二三", at: date, directory: tempDir)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "# 2026-05-02\n\n## 14:30:12\n\n測試一二三\n")
    }

    func test_append_secondCallAppendsEntryNotHeader() throws {
        let first = Self.makeDate(year: 2026, month: 5, day: 2, hour: 9, minute: 0, second: 0)
        let second = Self.makeDate(year: 2026, month: 5, day: 2, hour: 17, minute: 45, second: 30)

        _ = try NoteWriter.append(transcript: "早上的想法", at: first, directory: tempDir)
        let url = try NoteWriter.append(transcript: "下午的想法", at: second, directory: tempDir)

        let contents = try String(contentsOf: url, encoding: .utf8)
        let expected = """
        # 2026-05-02

        ## 09:00:00

        早上的想法

        ## 17:45:30

        下午的想法

        """
        XCTAssertEqual(contents, expected)
    }

    func test_append_differentDaysWriteToDifferentFiles() throws {
        let day1 = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        let day2 = Self.makeDate(year: 2026, month: 5, day: 3, hour: 12, minute: 0, second: 0)

        let url1 = try NoteWriter.append(transcript: "Day 1", at: day1, directory: tempDir)
        let url2 = try NoteWriter.append(transcript: "Day 2", at: day2, directory: tempDir)

        XCTAssertNotEqual(url1, url2)
        XCTAssertEqual(url1.lastPathComponent, "2026-05-02.md")
        XCTAssertEqual(url2.lastPathComponent, "2026-05-03.md")
    }

    func test_append_createsParentDirectoryIfMissing() throws {
        let nested = tempDir.appendingPathComponent("nested/path")
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)

        let url = try NoteWriter.append(transcript: "hello", at: date, directory: nested)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_append_preservesUnicodeAndNewlinesInsideTranscript() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        let body = "中文內容\n第二行"
        let url = try NoteWriter.append(transcript: body, at: date, directory: tempDir)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("中文內容\n第二行"))
    }

    // MARK: - Helpers

    /// Builds a Date in the system's current timezone so it round-trips through
    /// NoteWriter's formatters (which intentionally use TimeZone.current).
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
