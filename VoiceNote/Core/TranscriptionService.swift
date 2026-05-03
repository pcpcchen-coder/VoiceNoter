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

/// Wraps WhisperKit. `warmup` instantiates and downloads the model if needed.
final class TranscriptionService {
    private var whisperKit: WhisperKit?
    private(set) var loadedModel: String?

    var isReady: Bool { whisperKit != nil }

    /// Call once at app launch (or when the user changes models).
    /// - Parameters:
    ///   - modelName: e.g. `large-v3-turbo`
    ///   - onProgress: invoked for download progress in `[0, 1]`. Always invoked on @MainActor.
    private static let modelPathPrefix = "whisperkit_model_path_"

    func warmup(
        modelName: String,
        onProgress: @MainActor @escaping (Double) -> Void,
        onLoadingStarted: @MainActor @escaping () -> Void = {}
    ) async throws {
        Log.transcription.info("Warming up WhisperKit model=\(modelName, privacy: .public)")

        do {
            let cacheKey = Self.modelPathPrefix + modelName
            let modelFolder: URL

            if let cachedPath = UserDefaults.standard.string(forKey: cacheKey),
               FileManager.default.fileExists(atPath: cachedPath) {
                Log.transcription.info("Using cached model at \(cachedPath, privacy: .public)")
                modelFolder = URL(fileURLWithPath: cachedPath)
                await onProgress(0.8)
            } else {
                modelFolder = try await WhisperKit.download(
                    variant: modelName
                ) { progress in
                    Task { @MainActor in
                        onProgress(progress.fractionCompleted * 0.8)
                    }
                }
                UserDefaults.standard.set(modelFolder.path, forKey: cacheKey)
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
            await onProgress(1.0)
            Log.transcription.info("WhisperKit ready")
        } catch {
            Log.transcription.error("WhisperKit init failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError.underlying(error.localizedDescription)
        }
    }

    /// Transcribe a 16kHz mono PCM WAV file to text.
    /// `prompt` is best-effort: if the loaded tokenizer can't encode it, we silently skip it.
    func transcribe(
        audioURL: URL,
        prompt: String?,
        chineseVariant: String = "zh-Hant",
        topK: Int = 5,
        temperature: Float = 0.0,
        temperatureFallbackCount: Int = 5
    ) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.notReady
        }

        var options = DecodingOptions()
        options.language = "zh"
        options.task = .transcribe
        options.temperature = temperature
        options.topK = topK
        options.temperatureFallbackCount = temperatureFallbackCount
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = true

        if let prompt, !prompt.isEmpty,
           let tokens = encodePrompt(prompt, with: kit) {
            options.promptTokens = tokens
        }

        do {
            let results = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            let text = results
                .map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { throw TranscriptionError.empty }

            if chineseVariant == "zh-Hant" {
                return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
            } else {
                return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
            }
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
        // WhisperKit 0.9.x exposes `tokenizer` on the pipeline. The exact protocol
        // shape changes between minor versions, so we keep this defensive.
        guard let tokenizer = kit.tokenizer else { return nil }
        let encoded = tokenizer.encode(text: " " + text)
        return encoded.isEmpty ? nil : encoded
    }
}
