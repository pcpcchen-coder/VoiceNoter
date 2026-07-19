import Foundation
import WhisperKit

enum TranscriptionError: LocalizedError {
    case notReady
    case empty
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "WhisperKit 尚未準備好（可能模型還在下載）"
        case .empty: return "轉錄結果為空"
        case .underlying(let msg): return "轉錄失敗：\(msg)"
        }
    }
}

/// `Transcribing` 的 WhisperKit 實作。`warmup` 會（如需要）下載並載入模型。
///
/// 模型路徑快取透過注入的 `SettingsStore` 存取，快取 key 的組字集中在 `SettingsStore`。
final class WhisperKitTranscriber: Transcribing {
    private var whisperKit: WhisperKit?
    private(set) var loadedModel: String?
    private let settings: SettingsStore
    private let downloader: ModelDownloading

    init(settings: SettingsStore = SettingsStore(), downloader: ModelDownloading = WhisperKitModelDownloader()) {
        self.settings = settings
        self.downloader = downloader
    }

    var isReady: Bool { whisperKit != nil }

    /// App 啟動時（或使用者換模型時）呼叫。
    /// - Parameters:
    ///   - modelName: e.g. `openai_whisper-large-v3_turbo`
    ///   - onProgress: 下載進度 `[0, 1]`，一律在 `@MainActor` 觸發。
    func warmup(
        modelName: String,
        onProgress: @MainActor @escaping (Double) -> Void,
        onLoadingStarted: @MainActor @escaping () -> Void = {}
    ) async throws {
        Log.transcription.info("Warming up WhisperKit model=\(modelName, privacy: .public)")

        do {
            let modelFolder: URL

            if let cachedPath = settings.modelFolderPath(for: modelName),
               FileManager.default.fileExists(atPath: cachedPath) {
                Log.transcription.info("Using cached model at \(cachedPath, privacy: .public)")
                modelFolder = URL(fileURLWithPath: cachedPath)
                // Already on disk — the download is effectively 100% complete.
                await onProgress(1.0)
            } else {
                // Report the true download fraction (0…1); loading is signalled separately
                // via onLoadingStarted so the UI can show a real 0–100% download percentage.
                modelFolder = try await downloader.download(variant: modelName) { fraction in
                    onProgress(fraction)
                }
                settings.setModelFolderPath(modelFolder.path, for: modelName)
                Log.transcription.info("Model downloaded to \(modelFolder.path, privacy: .public)")
            }
            await onLoadingStarted()

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: true,
                logLevel: .info,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.loadedModel = modelName
            Log.transcription.info("WhisperKit ready")
        } catch {
            Log.transcription.error("WhisperKit init failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError.underlying(error.localizedDescription)
        }
    }

    /// 轉錄一段 16kHz mono PCM WAV。
    /// `settings.prompt` 為 best-effort：若 tokenizer 無法編碼就靜默略過。
    func transcribe(audioURL: URL, settings decoding: DecodingSettings) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.notReady
        }

        var options = DecodingOptions()
        options.language = decoding.language
        options.task = .transcribe
        options.temperature = decoding.temperature
        options.topK = decoding.topK
        options.temperatureFallbackCount = decoding.temperatureFallbackCount
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = true

        if let prompt = decoding.prompt, !prompt.isEmpty,
           let tokens = encodePrompt(prompt, with: kit) {
            options.promptTokens = tokens
        }

        do {
            let results = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            guard let text = TranscriptPostProcessor.process(
                segments: results.map { $0.text },
                variant: decoding.variant
            ) else {
                throw TranscriptionError.empty
            }
            return text
        } catch let e as TranscriptionError {
            throw e
        } catch {
            Log.transcription.error("Transcribe failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError.underlying(error.localizedDescription)
        }
    }

    /// Best-effort tokenization of an initial prompt. Different WhisperKit versions
    /// expose the tokenizer slightly differently; if anything goes wrong we just
    /// drop the prompt rather than failing the transcription.
    private func encodePrompt(_ text: String, with kit: WhisperKit) -> [Int]? {
        guard let tokenizer = kit.tokenizer else { return nil }
        let encoded = tokenizer.encode(text: " " + text)
        return encoded.isEmpty ? nil : encoded
    }
}
