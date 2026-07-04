import SwiftUI

struct OutputSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        Section("輸出方式") {
            Toggle(
                "辨識後自動輸入到游標位置",
                isOn: Binding(get: { state.pasteAtCursor }, set: { state.setPasteAtCursor($0) })
            )
            Text("開啟後，語音辨識結果會像輸入法一樣直接貼到游標所在位置。關閉則只複製到剪貼簿。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
