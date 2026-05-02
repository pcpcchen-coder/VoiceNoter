import SwiftUI
import KeyboardShortcuts
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: RecordingCoordinator

    var body: some View {
        Group {
            if state.micPermission == .denied {
                Button("麥克風權限未授予 → 開啟系統設定") {
                    PermissionHelper.openMicrophoneSettings()
                }
            } else {
                Text(statusLine).disabled(true)
            }

            if coordinator.modelLoadFailed {
                Button("重試模型載入") { coordinator.retryWarmup() }
            }

            if let error = state.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .disabled(true)
            }

            if !state.lastTranscript.isEmpty {
                Button("最近：\(previewSnippet(state.lastTranscript))") {
                    NoteWriter.openInDefaultApp(NoteWriter.todayNoteURL())
                }
            }

            Divider()

            Button("開啟今日筆記") {
                NoteWriter.openInDefaultApp(NoteWriter.todayNoteURL())
            }
            Button("在 Finder 顯示筆記資料夾") {
                NSWorkspace.shared.activateFileViewerSelecting([Paths.notesDirectory])
            }
            SettingsLink {
                Text("設定…")
            }

            Divider()

            Button("結束 VoiceNote") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var statusLine: String {
        let hotkeyDesc = KeyboardShortcuts.getShortcut(for: .pushToTalk)?.description ?? "未設定"
        switch state.state {
        case .idle:
            return "待機中 · 熱鍵 \(hotkeyDesc)"
        case .recording:
            return "錄音中…"
        case .transcribing:
            return "轉錄中…"
        case .error:
            return "發生錯誤"
        case .downloadingModel(let progress):
            return "下載模型中 \(Int(progress * 100))%"
        }
    }

    private func previewSnippet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 { return trimmed }
        let prefix = trimmed.prefix(30)
        return "\(prefix)…"
    }
}
