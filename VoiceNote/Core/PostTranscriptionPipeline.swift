import Foundation

/// 轉錄完成後的 AI 後處理：自動校稿與「幫我整理」。
///
/// 從 `RecordingCoordinator` 抽出，依賴注入的 `TextRewriting` 與 `NoteStoring`，
/// 並把結果訊息分流到 `AppState`（成功→`infoMessage` 灰字，失敗→`lastError` 紅字）。
@MainActor
struct PostTranscriptionPipeline {
    private let rewriter: TextRewriting
    private let noteStore: NoteStoring
    private let state: AppState

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    init(rewriter: TextRewriting, noteStore: NoteStoring, state: AppState) {
        self.rewriter = rewriter
        self.noteStore = noteStore
        self.state = state
    }

    /// 純函式：判斷轉錄文字是否為「整理」指令。
    static func detectOrganizeCommand(_ text: String) -> Bool {
        text.contains("幫我整理") || text.contains("請整理")
    }

    /// 自動校稿：把當日筆記最後一筆（剛落檔的原始逐字稿）換成 AI 校稿後版本。
    /// `enabled` 為 false 時直接返回（由設定控制）。
    func proofread(original: String, enabled: Bool, now: Date = Date()) async {
        guard enabled else { return }
        do {
            let proofread = try await rewriter.rewrite(original)
            // 用 replaceLastEntry（會拋錯，不再靜默）取代最後一次出現的原文，避免整檔改寫。
            try noteStore.replaceLastEntry(matching: original, with: proofread, now: now)
            state.noteInfo("已自動校稿")
        } catch {
            state.noteSoftFailure("AI 校稿失敗：\(error.localizedDescription)")
        }
    }

    /// 幫我整理：讀當日筆記，AI 整理後以「## AI 整理 (HH:mm)」新段落追加到末尾，
    /// 永不覆蓋原始內容。
    func organize(now: Date = Date()) async {
        state.noteInfo("AI 整理中…")
        do {
            let original = try noteStore.readToday(now: now)
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state.noteSoftFailure("今日尚無筆記可整理")
                return
            }
            let summary = try await rewriter.rewrite(original)
            let title = "AI 整理 (\(Self.timeFormatter.string(from: now)))"
            try noteStore.appendSection(title: title, body: summary, now: now)
            state.noteInfo("筆記已由 AI 整理")
        } catch {
            state.noteSoftFailure("AI 整理失敗：\(error.localizedDescription)")
        }
    }
}
