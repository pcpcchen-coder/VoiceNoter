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
    func warmup(
        modelName: String,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws {
        Log.transcription.info("Warming up WhisperKit model=\(modelName, privacy: .public)")

        do {
            // WhisperKit handles download + load internally. Models are cached under
            // ~/Documents/huggingface/models by default (controlled by HuggingFace
            // hub conventions).
            let kit = try await WhisperKit(model: modelName)
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
    func transcribe(audioURL: URL, prompt: String?) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.notReady
        }

        var options = DecodingOptions()
        options.language = "zh"
        options.task = .transcribe
        options.temperature = 0.0
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
        // WhisperKit 0.9.x exposes `tokenizer` on the pipeline. The exact protocol
        // shape changes between minor versions, so we keep this defensive.
        guard let tokenizer = kit.tokenizer else { return nil }
        let encoded = tokenizer.encode(text: " " + text)
        return encoded.isEmpty ? nil : encoded
    }
}
