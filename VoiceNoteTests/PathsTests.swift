import XCTest
@testable import VoiceNote

final class PathsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicenote-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_readGlossaryAsPrompt_returnsCommaJoinedTerms() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "EMS\nPCS\n寧德時代\n".write(to: file, atomically: true, encoding: .utf8)

        let prompt = Paths.readGlossaryAsPrompt(from: file)

        XCTAssertEqual(prompt, "EMS, PCS, 寧德時代")
    }

    func test_readGlossaryAsPrompt_skipsBlankAndWhitespaceLines() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "EMS\n\n   \n  PCS  \n".write(to: file, atomically: true, encoding: .utf8)

        let prompt = Paths.readGlossaryAsPrompt(from: file)

        XCTAssertEqual(prompt, "EMS, PCS")
    }

    func test_readGlossaryAsPrompt_returnsNilForMissingFile() {
        let missing = tempDir.appendingPathComponent("does-not-exist.txt")
        XCTAssertNil(Paths.readGlossaryAsPrompt(from: missing))
    }

    func test_readGlossaryAsPrompt_returnsNilForEmptyFile() throws {
        let file = tempDir.appendingPathComponent("glossary.txt")
        try "".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(Paths.readGlossaryAsPrompt(from: file))
    }

    func test_notesDirectory_isUnderUserDocuments() {
        let url = Paths.notesDirectory
        XCTAssertTrue(url.path.contains("Documents"))
        XCTAssertEqual(url.lastPathComponent, "VoiceNotes")
    }

    func test_appSupportDirectory_endsInVoiceNote() {
        let url = Paths.appSupportDirectory
        XCTAssertEqual(url.lastPathComponent, "VoiceNote")
    }

    func test_glossaryFile_livesInsideAppSupport() {
        let glossary = Paths.glossaryFile
        XCTAssertEqual(glossary.lastPathComponent, "glossary.txt")
        XCTAssertEqual(
            glossary.deletingLastPathComponent().path,
            Paths.appSupportDirectory.path
        )
    }
}
