import Foundation
import AppKit

struct NoteWriter {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Resolve the note file URL for a given day.
    /// `directory` defaults to the production notes folder; tests pass a temp URL.
    static func todayNoteURL(now: Date = Date(), directory: URL = Paths.notesDirectory) -> URL {
        let day = dayFormatter.string(from: now)
        return directory.appendingPathComponent("\(day).md")
    }

    @discardableResult
    static func append(
        transcript: String,
        at date: Date = Date(),
        directory: URL = Paths.notesDirectory
    ) throws -> URL {
        let url = todayNoteURL(now: date, directory: directory)
        let fm = FileManager.default

        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: url.path) {
            let header = "# \(dayFormatter.string(from: date))\n"
            try header.write(to: url, atomically: true, encoding: .utf8)
        }

        let entry = "\n## \(timeFormatter.string(from: date))\n\n\(transcript)\n"
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = entry.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }

        Log.note.info("Appended note to \(url.path, privacy: .public)")
        return url
    }

    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func pasteAtCursor(_ text: String) {
        copyToPasteboard(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cgSessionEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cgSessionEventTap)
        }
    }

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
