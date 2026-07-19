import Foundation

enum Paths {
    static var notesDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("VoiceNotes", isDirectory: true)
    }

    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VoiceNote", isDirectory: true)
    }

    static var glossaryFile: URL {
        appSupportDirectory.appendingPathComponent("glossary.txt")
    }

    static var modelsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("huggingface/models", isDirectory: true)
    }

    /// 把絕對路徑開頭的家目錄縮寫為 `~`，方便在設定頁顯示。找不到家目錄前綴時原樣回傳。
    static func displayPath(for url: URL, home: String = NSHomeDirectory()) -> String {
        displayPath(forPath: url.path, home: home)
    }

    /// `displayPath(for:)` 的純字串版本，`home` 可注入以便測試。
    static func displayPath(forPath path: String, home: String) -> String {
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !trimmedHome.isEmpty else { return path }
        if path == trimmedHome { return "~" }
        // 只在完整路徑元件邊界（/）比對，避免 /Users/foo 誤配到 /Users/foobar。
        if path.hasPrefix(trimmedHome + "/") {
            return "~" + path.dropFirst(trimmedHome.count)
        }
        return path
    }

    static func ensureDirectoriesExist() {
        let fm = FileManager.default
        for dir in [notesDirectory, appSupportDirectory, modelsDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    Log.app.info("Created directory: \(dir.path, privacy: .public)")
                } catch {
                    Log.app.error("Failed to create directory \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
