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

    static func todayNoteURL(now: Date = Date()) -> URL {
        let day = dayFormatter.string(from: now)
        return Paths.notesDirectory.appendingPathComponent("\(day).md")
    }

    @discardableResult
    static func append(transcript: String, at date: Date = Date()) throws -> URL {
        let url = todayNoteURL(now: date)
        let fm = FileManager.default

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

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
