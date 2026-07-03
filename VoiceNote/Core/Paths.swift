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
