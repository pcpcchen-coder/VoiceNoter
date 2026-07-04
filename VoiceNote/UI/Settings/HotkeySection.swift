import SwiftUI
import KeyboardShortcuts

struct HotkeySection: View {
    var body: some View {
        Section("熱鍵") {
            KeyboardShortcuts.Recorder("按住錄音", name: .pushToTalk)
            Text("按住熱鍵即錄音，放開立即停止並轉錄。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
