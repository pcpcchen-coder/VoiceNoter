import Foundation
@testable import VoiceNote

/// In-memory NoteStoring double: records appends and replace calls, injectable errors.
final class MockNoteStore: NoteStoring {
    var directory = URL(fileURLWithPath: "/tmp/voicenote-mock-notes")

    private(set) var appendedTranscripts: [String] = []
    var appendError: Error?

    private(set) var appendedSections: [(title: String, body: String)] = []
    var appendSectionError: Error?

    var readResult: Result<String, Error> = .success("")
    var replaceError: Error?
    private(set) var replaceCalls: [(original: String, replacement: String)] = []

    func append(transcript: String, at date: Date) throws -> URL {
        if let appendError { throw appendError }
        appendedTranscripts.append(transcript)
        return directory.appendingPathComponent("note.md")
    }

    func appendSection(title: String, body: String, now: Date) throws {
        if let appendSectionError { throw appendSectionError }
        appendedSections.append((title, body))
    }

    func todayNoteURL(now: Date) -> URL {
        directory.appendingPathComponent("note.md")
    }

    func readToday(now: Date) throws -> String {
        switch readResult {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }

    func replaceLastEntry(matching original: String, with replacement: String, now: Date) throws {
        replaceCalls.append((original, replacement))
        if let replaceError { throw replaceError }
    }
}
