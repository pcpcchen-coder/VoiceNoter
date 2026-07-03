import Foundation
import AppKit

/// 把轉錄結果交付到系統的抽象介面（剪貼簿／游標貼上），讓核心流程能注入 mock。
protocol TranscriptDelivering {
    /// 一律複製到剪貼簿；`pasteAtCursor` 為 true 時額外模擬 Cmd+V 貼到游標位置。
    func deliver(_ text: String, pasteAtCursor: Bool)
}

/// `TranscriptDelivering` 的系統實作：剪貼簿 + CGEvent 模擬貼上。
/// 另提供以預設 App 開檔的靜態工具（選單列使用）。
struct SystemTranscriptDeliverer: TranscriptDelivering {
    func deliver(_ text: String, pasteAtCursor: Bool) {
        Self.copyToPasteboard(text)
        guard pasteAtCursor else { return }

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

    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
