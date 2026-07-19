import Foundation
@testable import VoiceNote

/// 可設定回傳/拋錯並記錄呼叫參數的 `Transcribing` mock。
/// 供 Step 6 起的服務層測試與 Step 10 的流程測試共用。
final class MockTranscriber: Transcribing {
    var isReadyValue = true
    var isReady: Bool { isReadyValue }

    var warmupError: Error?
    private(set) var warmupCalls: [String] = []
    /// Download fractions emitted (in order) before `onLoadingStarted`, mirroring the real
    /// transcriber which reports true 0…1 download progress then switches to loading.
    var warmupProgressSequence: [Double] = []

    var transcribeResult: Result<String, Error> = .success("mock transcript")
    private(set) var transcribeCalls: [(url: URL, settings: DecodingSettings)] = []

    func warmup(
        modelName: String,
        onProgress: @MainActor @escaping (Double) -> Void,
        onLoadingStarted: @MainActor @escaping () -> Void
    ) async throws {
        warmupCalls.append(modelName)
        if let warmupError { throw warmupError }
        isReadyValue = true
        for fraction in warmupProgressSequence {
            await onProgress(fraction)
        }
        await onLoadingStarted()
    }

    func transcribe(audioURL: URL, settings: DecodingSettings) async throws -> String {
        transcribeCalls.append((audioURL, settings))
        switch transcribeResult {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}
