import SwiftUI
import AppKit

struct ModelSection: View {
    @ObservedObject var state: AppState
    @ObservedObject var download: ModelDownloadViewModel

    private static let availableModels: [(id: String, label: String)] = [
        ("openai_whisper-small", "small (~460 MB) — 快速，中文尚可"),
        ("openai_whisper-large-v3_turbo_954MB", "large-v3 turbo 壓縮版 (954 MB) — 推薦"),
        ("openai_whisper-large-v3_turbo", "large-v3 turbo 完整版 (~3 GB) — 最佳品質"),
        ("openai_whisper-large-v3_947MB", "large-v3 壓縮版 (947 MB) — 高準確度"),
        ("openai_whisper-large-v3", "large-v3 完整版 (~3 GB) — 最高準確度"),
        ("distil-whisper_distil-large-v3_turbo_600MB", "distil-large-v3 turbo (600 MB) — 輕量快速"),
    ]

    var body: some View {
        Section("模型") {
            Picker("Whisper 模型", selection: Binding(
                get: { state.selectedModel },
                set: { state.updateModelChoice($0) }
            )) {
                ForEach(Self.availableModels, id: \.id) { model in
                    Text(model.label).tag(model.id)
                }
            }

            if case .downloading(let progress) = download.status {
                ProgressView(value: progress) {
                    Text("下載中 \(Int(progress * 100))%").font(.caption)
                }
            } else {
                Button("預先下載所選模型") {
                    Task { await download.download(modelName: state.selectedModel) }
                }
            }

            statusText

            Text("切換後會自動重新載入模型，無需重啟 App。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            storageLocation
        }
    }

    /// 顯示模型檔存放位置，方便使用者管理／刪除大型模型檔。
    @ViewBuilder private var storageLocation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("模型儲存位置")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(download.modelsFolderDisplayPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            if let path = download.downloadedFolderDisplayPath(for: state.selectedModel) {
                Text("目前模型：\(path)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Button("在 Finder 開啟模型資料夾") {
            Paths.ensureDirectoriesExist()
            NSWorkspace.shared.open(Paths.modelsDirectory)
        }

        Text("大型模型檔存放於此，可在 Finder 中刪除不再使用的模型以釋放空間。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var statusText: some View {
        switch download.status {
        case .done(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
