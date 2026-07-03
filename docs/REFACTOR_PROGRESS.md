# VoiceNote 重構進度追蹤

> 搭配 [`REFACTOR_PLAN.md`](./REFACTOR_PLAN.md) 使用。
> 每完成一個 Step，更新下方進度表並 commit。

---

## 使用方式

對 Claude 說：

> 請完成 Step N

Claude（或任何執行者）必須遵守以下守則：

1. **先讀文件**：開工前重讀 `PROJECT_REVIEW.md`、`REFACTOR_PLAN.md` 中該 Step 的規格，以及本檔的進度表與備註。
2. **確認前置**：檢查該 Step 的前置 Step 是否已完成（見計畫中的相依關係圖）；未完成則先告知使用者，不要硬做。
3. **TDD 順序**：先寫計畫中列出的測試案例（紅）→ 最小實作（綠）→ 整理（重構）。測試案例名稱以計畫所列為準，實作中發現需要增補可以加、不可以砍。
4. **不夾帶**：只做該 Step 範圍內的變更。過程中發現的新問題：記到本檔的「發現的新問題」區，不要順手修。
5. **計畫可以改，但要留痕**：若實作時發現計畫需要調整（介面設計不合理、相依順序有誤），先修改 `REFACTOR_PLAN.md` 並在該 Step 備註欄說明原因，再繼續。
6. **驗證**：跑 `scripts/test.sh`（Step 1 之後）或請使用者在本機執行；CI 綠燈後才算完成。Claude 的遠端環境無法執行 `xcodebuild`，測試結果以 CI 為準。
7. **收尾**：更新本檔進度表（狀態、日期、commit）→ commit（訊息 `Step N: <標題>`）→ push 到工作分支。
8. **手動驗收**：規格中標注需手動 smoke test 的 Step，完成後明確列出請使用者在 Mac 上驗證的項目清單。

### 狀態代碼

- ⬜ 未開始　🔨 進行中　✅ 完成　⏸️ 暫停/等待決策　❌ 跳過（需在備註說明）

---

## 進度表

| Step | 標題 | 狀態 | 完成日期 | Commit | 備註 |
|------|------|------|----------|--------|------|
| 1 | 建立 CI 與測試基準線 | ✅ | 2026-07-03 | `51195ed` | CI workflow + `scripts/test.sh` 就緒；scheme 測試 action 本已正確無需改。[CI run #1](https://github.com/pcpcchen-coder/VoiceNoter/actions/runs/28639522161) **綠燈確認**（success，含既有 3 個測試檔） |
| 2 | `SettingsStore`：設定集中化與可注入 | ✅ | 2026-07-03 | `<this>` | 新增 `SettingsStore`（可注入 `UserDefaults`）與 18 個測試；`AppState` 改建構子注入、移除全部 UserDefaults 字面量；`AppStateTests` 改用隔離 suite 不再碰 shared（解 T2）。`chineseVariant` 暫留 `String`，Step 3 升級為 `ChineseVariant` |
| 3 | `TranscriptPostProcessor`：繁簡轉換純函式化 | ⬜ | | | |
| 4 | `NoteWriter` 拆分：Formatter + Store + 系統動作 | ⬜ | | | |
| 5 | `GlossaryStore`：詞表模組化 | ⬜ | | | |
| 6 | `Transcribing` 協定與模型快取集中 | ⬜ | | | |
| 7 | `OpenAIRewriter` 重構 | ⬜ | | | |
| 8 | `CredentialStore`：API Key 移入 Keychain | ⬜ | | | |
| 9 | 死碼大掃除 | ⬜ | | | |
| 10 | `RecordingCoordinator` 獨立化與依賴注入 | ⬜ | | | |
| 11 | `PostTranscriptionPipeline` 與 bug 修正 | ⬜ | | | |
| 12 | `RecorderState` 收斂 + 模型切換免重啟 | ⬜ | | | |
| 13 | `SettingsView` 拆分 + `ModelDownloader` 統一 | ⬜ | | | |
| 14 | 文件同步、最終清掃、手動驗收 | ⬜ | | | |

---

## 手動驗收紀錄

（附錄 A 清單的執行結果記在這裡，格式：日期 / 執行項目 / 結果）

| 日期 | 項目 | 結果 | 備註 |
|------|------|------|------|
| | | | |

---

## 發現的新問題

（重構過程中發現、但不屬於當前 Step 範圍的問題記在這裡，之後決定要不要排入計畫）

| 編號 | 發現於 | 描述 | 處理 |
|------|--------|------|------|
| | | | |

---

## 決策紀錄

（實作過程中偏離計畫的決定，附原因）

| 日期 | Step | 決策 | 原因 |
|------|------|------|------|
| 2026-07-03 | — | 建立本計畫；「幫我整理」改為追加段落而非整檔覆蓋（見 Step 11 行為決策） | 原實作有資料遺失風險（B3） |
| 2026-07-03 | 2 | `SettingsStore.chineseVariant` 維持 `String`，不在本步升級為 `ChineseVariant` | 型別化屬於 Step 3 範圍，避免夾帶（守則 4） |
| 2026-07-03 | 2 | 專案未用 Xcode 檔案系統同步群組，新 `.swift` 檔以手動 6 處編輯登記進 `project.pbxproj`（比照 `Paths.swift`） | 否則新檔不會被編譯 |
