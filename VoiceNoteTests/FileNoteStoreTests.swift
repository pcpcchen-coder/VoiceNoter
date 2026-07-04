import XCTest
@testable import VoiceNote

/// `FileNoteStore` 的檔案 IO 測試。沿用原 `NoteWriterTests` 的全部案例（改用注入的
/// temp 目錄），另加 `replaceLastEntry` 的成功與失敗路徑。
final class FileNoteStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: FileNoteStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = FileNoteStore(directory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_todayNoteURL_returnsYYYYMMDDFile() {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        let url = store.todayNoteURL(now: date)
        XCTAssertEqual(url.lastPathComponent, "2026-05-02.md")
        XCTAssertEqual(url.deletingLastPathComponent().path, tempDir.path)
    }

    func test_append_createsFileWithHeaderAndEntry() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 14, minute: 30, second: 12)
        let url = try store.append(transcript: "測試一二三", at: date)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "# 2026-05-02\n\n## 14:30:12\n\n測試一二三\n")
    }

    func test_append_secondCallAppendsEntryNotHeader() throws {
        let first = Self.makeDate(year: 2026, month: 5, day: 2, hour: 9, minute: 0, second: 0)
        let second = Self.makeDate(year: 2026, month: 5, day: 2, hour: 17, minute: 45, second: 30)

        _ = try store.append(transcript: "早上的想法", at: first)
        let url = try store.append(transcript: "下午的想法", at: second)

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

        let url1 = try store.append(transcript: "Day 1", at: day1)
        let url2 = try store.append(transcript: "Day 2", at: day2)

        XCTAssertNotEqual(url1, url2)
        XCTAssertEqual(url1.lastPathComponent, "2026-05-02.md")
        XCTAssertEqual(url2.lastPathComponent, "2026-05-03.md")
    }

    func test_append_createsParentDirectoryIfMissing() throws {
        let nested = tempDir.appendingPathComponent("nested/path")
        let nestedStore = FileNoteStore(directory: nested)
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)

        let url = try nestedStore.append(transcript: "hello", at: date)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_append_preservesUnicodeAndNewlinesInsideTranscript() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        let body = "中文內容\n第二行"
        let url = try store.append(transcript: body, at: date)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("中文內容\n第二行"))
    }

    // MARK: - replaceLastEntry

    func test_replaceLastEntry_rewritesLastMatchOnDisk() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        let url = try store.append(transcript: "原始逐字稿", at: date)

        try store.replaceLastEntry(matching: "原始逐字稿", with: "校稿後內容", now: date)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("校稿後內容"))
        XCTAssertFalse(contents.contains("原始逐字稿"))
    }

    func test_replaceLastEntry_throwsWhenOriginalNotFound() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        _ = try store.append(transcript: "某段內容", at: date)

        XCTAssertThrowsError(
            try store.replaceLastEntry(matching: "不存在的內容", with: "X", now: date)
        )
    }

    func test_appendSection_addsCustomTitledSection_andPreservesExistingContent() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 9, minute: 0, second: 0)
        _ = try store.append(transcript: "既有逐字稿", at: date)

        try store.appendSection(title: "AI 整理 (14:30)", body: "整理後摘要", now: date)

        let contents = try String(contentsOf: store.todayNoteURL(now: date), encoding: .utf8)
        XCTAssertTrue(contents.contains("既有逐字稿"), "original content must be preserved")
        XCTAssertTrue(contents.contains("## AI 整理 (14:30)\n\n整理後摘要\n"))
    }

    func test_readToday_returnsFileContents() throws {
        let date = Self.makeDate(year: 2026, month: 5, day: 2, hour: 12, minute: 0, second: 0)
        _ = try store.append(transcript: "可讀內容", at: date)

        let read = try store.readToday(now: date)
        XCTAssertTrue(read.contains("可讀內容"))
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
