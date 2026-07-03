import Foundation

/// 一次轉錄所需的解碼參數，值型別、無外部相依，方便測試與傳遞。
struct DecodingSettings: Equatable {
    var language: String = "zh"
    var topK: Int = 5
    var temperature: Float = 0
    var temperatureFallbackCount: Int = 5
    var prompt: String?
    var variant: ChineseVariant = .traditional
}

extension DecodingSettings {
    /// 便利建構：從使用者設定組出解碼參數，`prompt` 由呼叫端（詞表）提供。
    init(settings: SettingsStore, prompt: String?) {
        self.init(
            topK: settings.decodingTopK,
            temperature: settings.decodingTemperature,
            temperatureFallbackCount: settings.decodingFallbackCount,
            prompt: prompt,
            variant: settings.chineseVariant
        )
    }
}

/// 語音轉錄服務的抽象介面。
///
/// 以 protocol 讓核心流程（Step 10 的 `RecordingCoordinator`）能注入 mock，
/// 真正的 WhisperKit 實作見 `WhisperKitTranscriber`。
protocol Transcribing: AnyObject {
    /// 模型是否已載入、可以開始轉錄。
    var isReady: Bool { get }

    /// 下載（如需要）並載入模型。進度 callback 一律在 `@MainActor` 觸發。
    func warmup(
        modelName: String,
        onProgress: @MainActor @escaping (Double) -> Void,
        onLoadingStarted: @MainActor @escaping () -> Void
    ) async throws

    /// 轉錄一段 16kHz mono WAV，回傳整理後文字。
    func transcribe(audioURL: URL, settings: DecodingSettings) async throws -> String
}
