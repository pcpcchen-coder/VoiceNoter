import SwiftUI

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
        }
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
