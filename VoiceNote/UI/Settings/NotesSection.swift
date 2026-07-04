import SwiftUI
import AppKit

struct NotesSection: View {
    var body: some View {
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
    }
}
