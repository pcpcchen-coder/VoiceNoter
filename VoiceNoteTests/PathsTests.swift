import XCTest
@testable import VoiceNote

final class PathsTests: XCTestCase {

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
