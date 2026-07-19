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

    func test_modelsDirectory_livesUnderDocumentsHuggingface() {
        let url = Paths.modelsDirectory
        XCTAssertTrue(url.path.contains("Documents"))
        XCTAssertEqual(url.lastPathComponent, "models")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "huggingface")
    }

    // MARK: - displayPath (home abbreviation for the settings UI)

    func test_displayPath_abbreviatesHomePrefixWithTilde() {
        XCTAssertEqual(
            Paths.displayPath(forPath: "/Users/tester/Documents/huggingface/models", home: "/Users/tester"),
            "~/Documents/huggingface/models"
        )
    }

    func test_displayPath_leavesNonHomePathsUnchanged() {
        XCTAssertEqual(Paths.displayPath(forPath: "/opt/models", home: "/Users/tester"), "/opt/models")
    }

    func test_displayPath_handlesExactHome() {
        XCTAssertEqual(Paths.displayPath(forPath: "/Users/tester", home: "/Users/tester"), "~")
    }

    func test_displayPath_toleratesTrailingSlashInHome() {
        XCTAssertEqual(Paths.displayPath(forPath: "/Users/tester/Documents", home: "/Users/tester/"), "~/Documents")
    }

    func test_displayPath_doesNotMatchPartialPathComponent() {
        // A sibling dir whose name merely starts with the home path must NOT be abbreviated.
        XCTAssertEqual(Paths.displayPath(forPath: "/Users/tester2/x", home: "/Users/tester"), "/Users/tester2/x")
    }

    func test_displayPath_forModelsDirectory_startsWithTilde() {
        let display = Paths.displayPath(for: Paths.modelsDirectory)
        XCTAssertTrue(display.hasPrefix("~/"), "expected home-abbreviated path, got \(display)")
        XCTAssertTrue(display.hasSuffix("huggingface/models"))
    }
}
