import Foundation

/// 中文字形。
///
/// raw value 與既有 `UserDefaults` 儲存字串相容（`"zh-Hant"` / `"zh-Hans"`），
/// 因此舊版使用者的偏好設定升級後仍可正確載入。這是專案中唯一定義這兩個字串的地方。
enum ChineseVariant: String, CaseIterable {
    case traditional = "zh-Hant"
    case simplified  = "zh-Hans"

    /// 從可能為 `nil` 或無法辨識的原始字串解析，預設為繁體。
    init(rawValueOrDefault raw: String?) {
        self = raw.flatMap(ChineseVariant.init(rawValue:)) ?? .traditional
    }

    /// 套用到文字的 ICU `StringTransform` 識別碼（Hans↔Hant）。
    fileprivate var transformIdentifier: String {
        switch self {
        case .traditional: return "Hans-Hant"
        case .simplified:  return "Hant-Hans"
        }
    }
}

/// 將 WhisperKit 的原始 segment 陣列整理成最終輸出文字。
///
/// 這是一段無副作用的純函式邏輯，從 `TranscriptionService` 抽出，方便單元測試：
/// 串接 → 去頭尾空白 → 空字串回傳 `nil` → 依字形做繁簡轉換。
enum TranscriptPostProcessor {
    /// - Parameters:
    ///   - segments: WhisperKit 各段文字。
    ///   - variant: 目標中文字形。
    /// - Returns: 整理後的文字；若整理後為空則回傳 `nil`（呼叫端可據此判定「轉錄為空」）。
    static func process(segments: [String], variant: ChineseVariant) -> String? {
        let joined = segments
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }

        let transform = StringTransform(variant.transformIdentifier)
        return joined.applyingTransform(transform, reverse: false) ?? joined
    }
}
