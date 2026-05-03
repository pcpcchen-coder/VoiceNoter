// Please remove any old SettingsView.swift files to avoid resource conflicts.

import SwiftUI

/// App 設定頁，可直接控制 OpenAI OAuth 相關設定
struct OpenAISettingsView: View {
    @ObservedObject var oauthManager = OpenAIOAuthManager.shared

    var body: some View {
        Form {
            Section(header: Text("OpenAI OAuth 認證")) {
                Toggle(
                    "API 失敗時自動重新認證 (401時自動彈出登入)",
                    isOn: $oauthManager.autoReauthOn401
                )
                .help("若啟用，當遇到 401 Unauthorized 會自動啟動認證流程。")

                Button("強制重新登入") {
                    Task { await oauthManager.reauthorize() }
                }
                .help("手動重新啟動 OAuth 認證。").padding(.vertical, 4)

                Button("清除本地 Token") {
                    oauthManager.clearTokens()
                }
                .help("移除本地儲存的所有認證資訊。")
            }
        }
        .frame(minWidth: 320, maxWidth: 400)
        .padding()
    }
}

#if DEBUG
#Preview {
    OpenAISettingsView()
}
#endif
