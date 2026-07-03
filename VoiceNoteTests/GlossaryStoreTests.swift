import XCTest
@testable import VoiceNote

/// `GlossaryStore` 以注入的 temp 檔案測試，涵蓋 prompt 讀取（自 PathsTests 遷入）
/// 與首次啟動的 bootstrap 複製行為。
final class GlossaryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-glossary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - prompt()

    func test_prompt_returnsCommaJoinedTerms() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "EMS\nPCS\n寧德時代\n".write(to: file, atomically: true, encoding: .utf8)

        let store = GlossaryStore(fileURL: file)

        XCTAssertEqual(store.prompt(), "EMS, PCS, 寧德時代")
    }

    func test_prompt_skipsBlankAndWhitespaceLines() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "EMS\n\n   \n  PCS  \n".write(to: file, atomically: true, encoding: .utf8)

        let store = GlossaryStore(fileURL: file)

        XCTAssertEqual(store.prompt(), "EMS, PCS")
    }

    func test_prompt_returnsNilForMissingFile() {
        let missing = tempDir.appendingPathComponent("does-not-exist.txt")
        XCTAssertNil(GlossaryStore(fileURL: missing).prompt())
    }

    func test_prompt_returnsNilForEmptyFile() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(GlossaryStore(fileURL: file).prompt())
    }

    // MARK: - bootstrapIfNeeded()

    func test_bootstrap_copiesBundledDefaultWhenMissing() throws {
        let source = tempDir.appendingPathComponent("default_glossary.txt")
        try "EMS\n儲能\n".write(to: source, atomically: true, encoding: .utf8)
        let target = tempDir.appendingPathComponent("glossary.txt")

        let store = GlossaryStore(fileURL: target, defaultSource: source)
        store.bootstrapIfNeeded()

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "EMS\n儲能\n")
    }

    func test_bootstrap_doesNotOverwriteExistingFile() throws {
        let source = tempDir.appendingPathComponent("default_glossary.txt")
        try "預設內容\n".write(to: source, atomically: true, encoding: .utf8)
        let target = tempDir.appendingPathComponent("glossary.txt")
        try "使用者自訂\n".write(to: target, atomically: true, encoding: .utf8)

        let store = GlossaryStore(fileURL: target, defaultSource: source)
        store.bootstrapIfNeeded()

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "使用者自訂\n")
    }

    func test_bootstrap_noSourceIsNoop() {
        let target = tempDir.appendingPathComponent("glossary.txt")

        let store = GlossaryStore(fileURL: target, defaultSource: nil)
        store.bootstrapIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
