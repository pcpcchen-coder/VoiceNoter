import Foundation

/// 管理使用者詞表：首次啟動從 bundle 複製預設檔，並提供 WhisperKit 的 initialPrompt。
///
/// 邏輯自 `Paths` 遷出，讓 `Paths` 專職路徑。來源檔以 URL 注入（預設走 `Bundle.main`），
/// 避免測試需要偽造 bundle。
struct GlossaryStore {
    private let fileURL: URL
    private let defaultSource: URL?

    init(
        fileURL: URL = Paths.glossaryFile,
        defaultSource: URL? = Bundle.main.url(forResource: "default_glossary", withExtension: "txt")
    ) {
        self.fileURL = fileURL
        self.defaultSource = defaultSource
    }

    /// 首次啟動：詞表檔不存在時，從內建的 default_glossary.txt 複製一份。
    func bootstrapIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        guard let source = defaultSource else {
            Log.app.error("default_glossary.txt missing from bundle")
            return
        }
        do {
            try fm.copyItem(at: source, to: fileURL)
            Log.app.info("Bootstrapped glossary at \(fileURL.path, privacy: .public)")
        } catch {
            Log.app.error("Failed to bootstrap glossary: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 讀詞表（每行一個詞），去頭尾空白、濾除空行，以逗號串接成 initialPrompt。
    /// 檔案不存在或無有效詞時回傳 `nil`。
    func prompt() -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
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
