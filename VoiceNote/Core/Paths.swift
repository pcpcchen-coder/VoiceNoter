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

    /// First-launch bootstrap: copy bundled default_glossary.txt into Application Support.
    static func bootstrapGlossaryIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: glossaryFile.path) else { return }

        guard let bundled = Bundle.main.url(forResource: "default_glossary", withExtension: "txt") else {
            Log.app.error("default_glossary.txt missing from bundle")
            return
        }

        do {
            try fm.copyItem(at: bundled, to: glossaryFile)
            Log.app.info("Bootstrapped glossary at \(glossaryFile.path, privacy: .public)")
        } catch {
            Log.app.error("Failed to bootstrap glossary: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads glossary terms (one per line) and joins with comma for WhisperKit initial prompt.
    static func readGlossaryAsPrompt() -> String? {
        guard let contents = try? String(contentsOf: glossaryFile, encoding: .utf8) else {
            return nil
        }
        let terms = contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ")
    }
}
