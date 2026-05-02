import SwiftUI
import KeyboardShortcuts
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    private static let availableModels = [
        "tiny",
        "base",
        "small",
        "medium",
        "large-v3",
        "large-v3-turbo"
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
                    ForEach(Self.availableModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("變更後請結束 VoiceNote 並重新啟動以套用新模型。")
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
        .frame(width: 480, height: 480)
        .padding()
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
