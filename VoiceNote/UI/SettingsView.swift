import SwiftUI
import KeyboardShortcuts
import AppKit
import WhisperKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var oauthManager = OpenAIOAuthManager.shared
    @State private var apiKeyInput: String = ""
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus: String?

    private static let availableModels: [(id: String, label: String)] = [
        ("openai_whisper-small", "small (~460 MB) — 快速，中文尚可"),
        ("openai_whisper-large-v3_turbo_954MB", "large-v3 turbo 壓縮版 (954 MB) — 推薦"),
        ("openai_whisper-large-v3_turbo", "large-v3 turbo 完整版 (~3 GB) — 最佳品質"),
        ("openai_whisper-large-v3_947MB", "large-v3 壓縮版 (947 MB) — 高準確度"),
        ("openai_whisper-large-v3", "large-v3 完整版 (~3 GB) — 最高準確度"),
        ("distil-whisper_distil-large-v3_turbo_600MB", "distil-large-v3 turbo (600 MB) — 輕量快速"),
    ]

    var body: some View {
        Form {
            Section("熱鍵") {
                KeyboardShortcuts.Recorder("按住錄音", name: .pushToTalk)
                Text("按住熱鍵即錄音，放開立即停止並轉錄。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("模型") {
                Picker("Whisper 模型", selection: Binding(
                    get: { state.selectedModel },
                    set: { state.updateModelChoice($0) }
                )) {
                    ForEach(Self.availableModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                if isDownloading {
                    ProgressView(value: downloadProgress) {
                        Text("下載中 \(Int(downloadProgress * 100))%")
                            .font(.caption)
                    }
                } else {
                    Button("預先下載所選模型") {
                        downloadSelectedModel()
                    }
                }

                if let status = downloadStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("變更後請結束 VoiceNote 並重新啟動以套用新模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("輸出方式") {
                Toggle(
                    "辨識後自動輸入到游標位置",
                    isOn: Binding(
                        get: { state.pasteAtCursor },
                        set: { state.setPasteAtCursor($0) }
                    )
                )
                Text("開啟後，語音辨識結果會像輸入法一樣直接貼到游標所在位置。關閉則只複製到剪貼簿。需要輔助使用權限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI 校稿") {
                Toggle(
                    "語音轉錄後自動校稿",
                    isOn: Binding(
                        get: { state.autoProofread },
                        set: { state.setAutoProofread($0) }
                    )
                )
                Text("開啟後，每次語音轉錄完成會自動透過 OpenAI 校正文字，需先設定 API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI 認證") {
                LabeledContent("認證狀態") {
                    if oauthManager.accessToken != nil {
                        Text("已認證")
                            .foregroundStyle(.green)
                    } else {
                        Text("未認證")
                            .foregroundStyle(.secondary)
                    }
                }

                SecureField("輸入 OpenAI API Key", text: $apiKeyInput)
                    .onSubmit { saveAPIKey() }

                Button("儲存 API Key") { saveAPIKey() }
                    .disabled(apiKeyInput.isEmpty)

                Button("清除認證資訊") {
                    oauthManager.clearTokens()
                }

                Toggle(
                    "API 失敗時自動重新認證",
                    isOn: Binding(
                        get: { oauthManager.autoReauthOn401 },
                        set: { oauthManager.setAutoReauthOn401($0) }
                    )
                )
                .help("若啟用，當遇到 401 Unauthorized 會自動啟動認證流程。")
            }

            Section("OpenAI 網頁登入 (OAuth)") {
                TextField("Client ID", text: $oauthManager.clientID)
                    .disabled(true)
                TextField("Redirect URI", text: $oauthManager.redirectURI)
                    .disabled(true)

                Button("透過網頁登入 OpenAI") {
                    Task { await oauthManager.login() }
                }
                .disabled(true)

                Text("尚未開放 — OpenAI 目前未提供第三方 OAuth App 註冊，請使用上方 API Key 認證。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("筆記") {
                LabeledContent("筆記儲存路徑") {
                    Text(Paths.notesDirectory.path)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("在 Finder 顯示") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.notesDirectory])
                }
                Button("編輯詞表（glossary.txt）") {
                    NSWorkspace.shared.open(Paths.glossaryFile)
                }
            }

            Section("關於") {
                LabeledContent("版本") {
                    Text(versionString)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
        .padding()
    }

    private func downloadSelectedModel() {
        isDownloading = true
        downloadProgress = 0
        downloadStatus = nil
        Task {
            do {
                let modelFolder = try await WhisperKit.download(
                    variant: state.selectedModel
                ) { progress in
                    Task { @MainActor in
                        downloadProgress = progress.fractionCompleted
                    }
                }
                let cacheKey = "whisperkit_model_path_\(state.selectedModel)"
                UserDefaults.standard.set(modelFolder.path, forKey: cacheKey)
                isDownloading = false
                downloadStatus = "模型已下載完成，重啟 App 即可使用。"
            } catch {
                isDownloading = false
                downloadStatus = "下載失敗：\(error.localizedDescription)"
            }
        }
    }

    private func saveAPIKey() {
        guard !apiKeyInput.isEmpty else { return }
        oauthManager.setAccessToken(apiKeyInput)
        apiKeyInput = ""
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView().environmentObject(AppState.shared)
}
