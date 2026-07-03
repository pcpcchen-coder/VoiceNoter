import Foundation
import AppKit

/// 將轉錄結果送到系統：剪貼簿、模擬貼上（CGEvent Cmd+V）到游標位置、以預設 App 開檔。
///
/// 目前維持具體型別（靜態方法，與原 `NoteWriter` 一致）；Step 10 會 protocol 化
/// 成 `TranscriptDelivering` 以便注入。
enum TranscriptDeliverer {
    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func pasteAtCursor(_ text: String) {
        copyToPasteboard(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cgSessionEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cgSessionEventTap)
        }
    }

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
