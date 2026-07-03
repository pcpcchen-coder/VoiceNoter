import Foundation

/// 當日 Markdown 筆記的儲存介面。
///
/// 抽成 protocol 是為了讓核心流程（Step 10 的 `RecordingCoordinator`）能注入 mock，
/// 而不必碰真實檔案系統。格式一律委派給 `NoteFormatter`。
protocol NoteStoring {
    @discardableResult
    func append(transcript: String, at date: Date) throws -> URL
    func todayNoteURL(now: Date) -> URL
    func readToday(now: Date) throws -> String
    func replaceLastEntry(matching original: String, with replacement: String, now: Date) throws
}

enum NoteStoreError: LocalizedError {
    case entryNotFound

    var errorDescription: String? {
        switch self {
        case .entryNotFound: return "找不到要取代的筆記內容"
        }
    }
}

/// 以檔案系統實作的筆記儲存。目錄於建構時綁定，測試可注入 temp 目錄。
final class FileNoteStore: NoteStoring {
    private let directory: URL

    init(directory: URL = Paths.notesDirectory) {
        self.directory = directory
    }

    func todayNoteURL(now: Date = Date()) -> URL {
        directory.appendingPathComponent(NoteFormatter.fileName(for: now))
    }

    @discardableResult
    func append(transcript: String, at date: Date = Date()) throws -> URL {
        let url = todayNoteURL(now: date)
        let fm = FileManager.default

        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: url.path) {
            try NoteFormatter.header(for: date).write(to: url, atomically: true, encoding: .utf8)
        }

        // Append 用 FileHandle，避免重讀整個檔案。
        let entry = NoteFormatter.entry(transcript: transcript, at: date)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = entry.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }

        Log.note.info("Appended note to \(url.path, privacy: .public)")
        return url
    }

    func readToday(now: Date = Date()) throws -> String {
        try String(contentsOf: todayNoteURL(now: now), encoding: .utf8)
    }

    /// 讀出當日筆記、取代最後一次出現的 `original`、寫回。
    /// 找不到 `original` 時拋 `NoteStoreError.entryNotFound`（不再靜默失敗）。
    func replaceLastEntry(matching original: String, with replacement: String, now: Date = Date()) throws {
        let url = todayNoteURL(now: now)
        let content = try String(contentsOf: url, encoding: .utf8)
        guard let updated = NoteFormatter.replacingLastOccurrence(of: original, with: replacement, in: content) else {
            throw NoteStoreError.entryNotFound
        }
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }
}
