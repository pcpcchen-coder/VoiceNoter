import Foundation

/// 設定頁「預先下載模型」的狀態機，包一個 `ModelDownloading`，把下載結果寫進 `SettingsStore`。
@MainActor
final class ModelDownloadViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case done(message: String)
        case failed(message: String)
    }

    @Published private(set) var status: Status = .idle

    private let downloader: ModelDownloading
    private let settings: SettingsStore

    init(downloader: ModelDownloading = WhisperKitModelDownloader(), settings: SettingsStore) {
        self.downloader = downloader
        self.settings = settings
    }

    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    /// 所有 Whisper 模型下載後存放的根資料夾（家目錄縮寫為 `~`），供設定頁顯示。
    var modelsFolderDisplayPath: String {
        Paths.displayPath(for: Paths.modelsDirectory)
    }

    /// 指定模型若已下載，回傳其本地資料夾的顯示路徑（家目錄縮寫為 `~`）；未下載回 `nil`。
    func downloadedFolderDisplayPath(for modelName: String) -> String? {
        guard let path = settings.modelFolderPath(for: modelName) else { return nil }
        return Paths.displayPath(forPath: path, home: NSHomeDirectory())
    }

    func download(modelName: String) async {
        guard !isDownloading else { return }   // 防止並行下載
        status = .downloading(progress: 0)
        do {
            let folder = try await downloader.download(variant: modelName) { [weak self] fraction in
                guard let self, self.isDownloading else { return }
                self.status = .downloading(progress: fraction)
            }
            settings.setModelFolderPath(folder.path, for: modelName)
            status = .done(message: "模型已下載完成，可直接使用。")
        } catch {
            status = .failed(message: "下載失敗：\(error.localizedDescription)")
        }
    }
}
