import Foundation

/// 使用者設定的唯一存取入口。
///
/// 集中管理所有 `UserDefaults` key 與預設值，並可注入自訂的 `UserDefaults`
/// （例如測試用的隔離 suite），讓設定邏輯得以在不汙染正式偏好設定的情況下被測試。
///
/// 注意：模型路徑快取（Step 6）與 OpenAI 憑證（Step 8）尚未納入本 store，
/// 會在後續步驟遷入，屆時本型別成為所有偏好設定的單一事實來源。
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 所有偏好設定 key 的集中定義。key 字串只允許出現在此。
    private enum Key: String {
        case selectedModel
        case autoProofread
        case chineseVariant
        case pasteAtCursor
        case decodingTopK
        case decodingTemperature
        case decodingFallbackCount
    }

    // MARK: - 預設值

    static let defaultModel = "openai_whisper-large-v3_turbo"
    static let defaultTopK = 5
    static let defaultTemperature: Float = 0.0
    static let defaultFallbackCount = 5

    /// 舊模型名稱 → WhisperKit 變體名稱的一次性遷移表。
    /// 讀取 `selectedModel` 時若命中舊名，會回寫新名並回傳新名。
    static let modelNameMigration: [String: String] = [
        "tiny": "openai_whisper-small",
        "base": "openai_whisper-small",
        "small": "openai_whisper-small",
        "medium": "openai_whisper-large-v3_turbo_954MB",
        "large-v2": "openai_whisper-large-v3_turbo_954MB",
        "large-v3": "openai_whisper-large-v3",
        "large-v3-turbo": "openai_whisper-large-v3_turbo",
        "openai_whisper-large-v2": "openai_whisper-large-v3_turbo_954MB",
    ]

    // MARK: - 設定項

    /// 選用的 Whisper 模型。讀取時會套用舊名遷移（見 `modelNameMigration`）。
    var selectedModel: String {
        get {
            let raw = defaults.string(forKey: Key.selectedModel.rawValue) ?? Self.defaultModel
            if let migrated = Self.modelNameMigration[raw] {
                defaults.set(migrated, forKey: Key.selectedModel.rawValue)
                return migrated
            }
            return raw
        }
        set { defaults.set(newValue, forKey: Key.selectedModel.rawValue) }
    }

    /// 轉錄後是否自動送 OpenAI 校稿。預設關閉。
    var autoProofread: Bool {
        get { defaults.bool(forKey: Key.autoProofread.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoProofread.rawValue) }
    }

    /// 中文字形。預設繁體。持久化格式為 `ChineseVariant` 的 raw value 字串，
    /// 與舊版儲存相容。
    var chineseVariant: ChineseVariant {
        get { ChineseVariant(rawValueOrDefault: defaults.string(forKey: Key.chineseVariant.rawValue)) }
        set { defaults.set(newValue.rawValue, forKey: Key.chineseVariant.rawValue) }
    }

    /// 辨識後是否自動貼到游標位置。預設開啟。
    var pasteAtCursor: Bool {
        get { defaults.object(forKey: Key.pasteAtCursor.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pasteAtCursor.rawValue) }
    }

    /// 解碼 Top-K。預設 5。
    var decodingTopK: Int {
        get { defaults.object(forKey: Key.decodingTopK.rawValue) as? Int ?? Self.defaultTopK }
        set { defaults.set(newValue, forKey: Key.decodingTopK.rawValue) }
    }

    /// 解碼取樣溫度。預設 0.0（greedy）。
    var decodingTemperature: Float {
        get { defaults.object(forKey: Key.decodingTemperature.rawValue) as? Float ?? Self.defaultTemperature }
        set { defaults.set(newValue, forKey: Key.decodingTemperature.rawValue) }
    }

    /// 溫度重試次數。預設 5。
    var decodingFallbackCount: Int {
        get { defaults.object(forKey: Key.decodingFallbackCount.rawValue) as? Int ?? Self.defaultFallbackCount }
        set { defaults.set(newValue, forKey: Key.decodingFallbackCount.rawValue) }
    }
}
