import SwiftUI
import KeyboardShortcuts
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if state.micPermission == .denied {
                Button("麥克風權限未授予 → 開啟系統設定") {
                    PermissionHelper.openMicrophoneSettings()
                }
            } else {
                Text(statusLine).disabled(true)
            }

            if case .error = state.state {
                Button("重試模型載入") { coordinator.retryWarmup() }
            }

            if let error = state.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .disabled(true)
            }

            if let info = state.infoMessage {
                Text(info)
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }

            if !state.lastTranscript.isEmpty {
                Button("最近：\(previewSnippet(state.lastTranscript))") {
                    SystemTranscriptDeliverer.openInDefaultApp(todayNoteURL)
                }
            }

            Divider()

            Button(state.chineseVariant == .traditional ? "✓ 繁體中文" : "　繁體中文") {
                state.setChineseVariant(.traditional)
            }
            Button(state.chineseVariant == .simplified ? "✓ 簡體中文" : "　簡體中文") {
                state.setChineseVariant(.simplified)
            }

            Divider()

            Button("開啟今日筆記") {
                SystemTranscriptDeliverer.openInDefaultApp(todayNoteURL)
            }
            Button("在 Finder 顯示筆記資料夾") {
                NSWorkspace.shared.activateFileViewerSelecting([Paths.notesDirectory])
            }
            Button("設定…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }

            Divider()

            Button("結束 VoiceNote") {
                NSApplication.shared.terminate(nil)
            }
        }
        // B9: refresh the mic permission each time the menu opens, so a change made in
        // System Settings is reflected without relaunching.
        .onAppear { state.refreshMicPermission() }
    }

    /// 當日筆記檔路徑（用正式筆記目錄）。Step 10 依賴注入後改由 store 提供。
    private var todayNoteURL: URL {
        FileNoteStore().todayNoteURL()
    }

    private var statusLine: String {
        let hotkeyDesc = KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "未設定"
        return MenuStatusText.line(state: state.state, hotkeyDescription: hotkeyDesc)
    }

    private func previewSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 { return trimmed }
        let prefix = trimmed.prefix(30)
        return "\(prefix)…"
    }
}
