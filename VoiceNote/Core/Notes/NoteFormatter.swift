import Foundation

/// 純函式的 Markdown 筆記格式邏輯，無任何檔案 IO。
///
/// 日期／時間格式沿用原 `NoteWriter` 的設定：`en_US_POSIX` locale、系統當前時區
/// （刻意不設 `timeZone`，讓輸出跟隨使用者所在時區）。
enum NoteFormatter {
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

    /// 當日筆記檔名，如 `2026-05-02.md`。
    static func fileName(for date: Date) -> String {
        "\(dayFormatter.string(from: date)).md"
    }

    /// 檔頭：H1 日期 + 換行。
    static func header(for date: Date) -> String {
        "# \(dayFormatter.string(from: date))\n"
    }

    /// 單筆紀錄：前置空行 + H2 時間 + 空行 + 內容 + 換行。
    static func entry(transcript: String, at date: Date) -> String {
        "\n## \(timeFormatter.string(from: date))\n\n\(transcript)\n"
    }

    /// 將 `text` 中「最後一次」出現的 `target` 換成 `replacement`。
    /// 找不到時回傳 `nil`，讓呼叫端可據此拋錯而非靜默略過（為 Step 11 修 B4 鋪路）。
    static func replacingLastOccurrence(of target: String, with replacement: String, in text: String) -> String? {
        guard let range = text.range(of: target, options: .backwards) else { return nil }
        var copy = text
        copy.replaceSubrange(range, with: replacement)
        return copy
    }
}
