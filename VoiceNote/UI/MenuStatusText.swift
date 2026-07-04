import Foundation

/// 選單列狀態文字的純函式邏輯，從 `MenuBarView` 抽出以便測試。
enum MenuStatusText {
    static func line(state: RecorderState, hotkeyDescription: String) -> String {
        switch state {
        case .idle:
            return "待機中 · 熱鍵 \(hotkeyDescription)"
        case .recording:
            return "錄音中…"
        case .transcribing:
            return "轉錄中…"
        case .error:
            return "發生錯誤"
        case .downloadingModel(let progress):
            return "下載模型中 \(Int(progress * 100))%"
        case .loadingModel:
            return "載入模型中（首次可能需要數分鐘）…"
        }
    }
}
