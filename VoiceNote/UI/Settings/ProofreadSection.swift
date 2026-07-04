import SwiftUI

struct ProofreadSection: View {
    @ObservedObject var state: AppState
    @ObservedObject var credentials: CredentialsViewModel
    @State private var apiKeyInput: String = ""

    var body: some View {
        Group {
            Section("AI 校稿") {
                Toggle(
                    "語音轉錄後自動校稿",
                    isOn: Binding(get: { state.autoProofread }, set: { state.setAutoProofread($0) })
                )
                Text("開啟後，每次語音轉錄完成會自動透過 OpenAI 校正文字，需先設定 API Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI 認證") {
                LabeledContent("認證狀態") {
                    if credentials.isAuthenticated {
                        Text("已認證").foregroundStyle(.green)
                    } else {
                        Text("未認證").foregroundStyle(.secondary)
                    }
                }

                SecureField("輸入 OpenAI API Key", text: $apiKeyInput)
                    .onSubmit { saveAPIKey() }

                Button("儲存 API Key") { saveAPIKey() }
                    .disabled(apiKeyInput.isEmpty)

                Button("清除認證資訊") { credentials.clear() }
            }
        }
    }

    private func saveAPIKey() {
        credentials.save(apiKeyInput)
        apiKeyInput = ""
    }
}
