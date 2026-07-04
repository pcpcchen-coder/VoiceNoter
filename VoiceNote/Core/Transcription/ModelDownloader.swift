import Foundation
import WhisperKit

/// 下載 Whisper 模型的抽象介面。讓暖機（`WhisperKitTranscriber`）與設定頁預下載共用同一實作，
/// 並可注入 mock 測試下載流程。
protocol ModelDownloading {
    /// 下載指定變體，回傳本地資料夾 URL；`progress` 在 `[0, 1]`，一律於 `@MainActor` 觸發。
    func download(variant: String, progress: @escaping @MainActor (Double) -> Void) async throws -> URL
}

/// WhisperKit 實作。
struct WhisperKitModelDownloader: ModelDownloading {
    func download(variant: String, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        try await WhisperKit.download(variant: variant) { fraction in
            Task { @MainActor in progress(fraction.fractionCompleted) }
        }
    }
}
