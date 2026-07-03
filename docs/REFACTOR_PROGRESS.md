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
| 3 | `TranscriptPostProcessor`：繁簡轉換純函式化 | ✅ | 2026-07-03 | `<this>` | 新增 `Core/Transcription/` 群組與 `TranscriptPostProcessor`（含 `ChineseVariant` 型別）；轉錄的 join/trim/empty/繁簡轉換抽成純函式並加 8 個測試；`chineseVariant` 全鏈升級為 `ChineseVariant`（SettingsStore/AppState/MenuBarView/TranscriptionService），持久化維持 raw string 相容。DoD 達成：StringTransform 與繁簡字面量只存在於 ChineseVariant 定義 |
| 4 | `NoteWriter` 拆分：Formatter + Store + 系統動作 | ✅ | 2026-07-03 | `<this>` | `NoteWriter` 拆成 `Core/Notes/NoteFormatter`（純格式）、`Core/Notes/NoteStore`（`NoteStoring` protocol + `FileNoteStore`，含拋錯的 `replaceLastEntry`）、`Core/Output/TranscriptDeliverer`（剪貼簿/貼上/開檔）；既有 6 個筆記測試遷入 `FileNoteStoreTests` + 3 純函式測試於 `NoteFormatterTests`；刪除 `NoteWriter.swift`/`NoteWriterTests.swift`。coordinator 的校稿字串手術暫維持原狀（Step 11 才用 replaceLastEntry 修 B4） |
| 5 | `GlossaryStore`：詞表模組化 | ✅ | 2026-07-03 | `<this>` | 新增 `Core/GlossaryStore.swift`（`bootstrapIfNeeded` + `prompt`），自 `Paths` 遷出；`Paths` 只剩路徑常量與 `ensureDirectoriesExist`（DoD 達成）；4 個 glossary 測試自 `PathsTests` 遷入 `GlossaryStoreTests` 並加 3 個 bootstrap 測試；`VoiceNoteApp` 改用 `GlossaryStore`。**Phase 1 完成** |
| 6 | `Transcribing` 協定與模型快取集中 | ✅ | 2026-07-03 | `<this>` | 新增 `Transcribing` 協定 + `DecodingSettings`（值型別，`init(settings:prompt:)`）；`TranscriptionService`→`WhisperKitTranscriber` 移入 `Core/Transcription/` 並 conform，6 參數 transcribe 收斂為 `DecodingSettings`；模型路徑快取集中到 `SettingsStore.modelFolderPath(for:)`；新增 `MockTranscriber`（Mocks 群組）+ `DecodingSettingsTests` + 2 個快取測試。DoD 達成：`whisperkit_model_path` 只在 SettingsStore、`import WhisperKit` 只在 WhisperKitTranscriber/SettingsView。**Phase 2 起步** |
| 7 | `OpenAIRewriter` 重構 | ✅ | 2026-07-03 | `<this>` | 新增 `Core/AI/`：`TextRewriting`/`CredentialProviding` 協定 + `OpenAIRewriter`（Codable、可注入 `URLSession`、型別化 `OpenAIRewriterError`）；`OpenAIRewriterTests` 以 `URLProtocol` stub 涵蓋 5 案例（不連網）；新增 `MockRewriter`；coordinator 改用注入的 `TextRewriting`；刪除 `AIRewriter.swift`。DoD：rewriter 路徑已無 `JSONSerialization`（剩餘唯一使用在 `OpenAIOAuthManager`，Step 9 整檔刪除） |
| 8 | `CredentialStore`：API Key 移入 Keychain | ✅ | 2026-07-03 | `<this>` | 新增 `Core/Credentials/`：`CredentialStoring` 協定 + `KeychainCredentialStore`（generic password）+ `migrateLegacyToken`（啟動時把舊 UserDefaults token 搬進 Keychain 並清 key）+ `CredentialsViewModel`；`SettingsView` 認證狀態/儲存/清除改走 VM；`OpenAIRewriter` 憑證改注入 `KeychainCredentialStore`。測試：`CredentialMigrationTests` + `InMemoryCredentialStore`（不碰真 Keychain，避 CI 簽章問題）。真 Keychain round-trip 屬手動驗收（同 WhisperKit adapter 策略） |
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
| 2026-07-03 | 4 | `NoteWriter.revealInFinder`（D4 死碼）隨 `NoteWriter.swift` 刪除一併移除，未遷入 `TranscriptDeliverer` | 無任何呼叫端；為死碼遷移只為 Step 9 再刪除無意義 |
| 2026-07-03 | 4 | coordinator 尚未做依賴注入（Step 10），暫以 `FileNoteStore()`／`TranscriptDeliverer` 靜態方法直接呼叫；MenuBarView 亦以 `FileNoteStore()` 取當日路徑 | 保持本步為純搬移、行為不變；DI 屬 Step 10 範圍 |
| 2026-07-03 | 5 | `GlossaryStore` 建構子改用 `defaultSource: URL?`（預設 `Bundle.main` 查找）而非計畫原訂的 `bundle: Bundle` | 用 Bundle 注入來測 bootstrap 需在 macOS 偽造 bundle 資源查找，脆弱不可靠；改注入來源 URL 可直接用 temp 檔測試，行為不變。已同步更新 `REFACTOR_PLAN.md` Step 5 |
| 2026-07-03 | 6 | `AppState.settings` 由 `private` 改為 internal `let`，供 coordinator/SettingsView 組 `DecodingSettings` 與存取模型快取 | Step 10 會把 settings 改為對 coordinator 顯式注入；本步先開放讀取，避免重複建立 SettingsStore 實例 |
| 2026-07-03 | 6 | `WhisperKitTranscriber(settings:)` 注入 SettingsStore 以存取模型路徑快取；coordinator 以 `state.settings` 傳入 | 讓快取與 AppState 用同一 store；預設參數 `SettingsStore()` 亦指向 standard，行為不變 |
| 2026-07-03 | 7 | `OpenAIOAuthManager` 過渡期 conform `CredentialProviding`，以 `nonisolated var apiKey` 直讀 UserDefaults token | @MainActor 類別無法用同步屬性滿足 nonisolated 協定；直讀已持久化的 token 可避開 actor 隔離，且 Step 8/9 即替換／刪除 |
| 2026-07-03 | 7 | DoD「專案內無 JSONSerialization」在本步僅對 rewriter 路徑達成；`OpenAIOAuthManager` 仍有殘留 | 該檔為死 OAuth 碼，Step 9 整檔刪除後 DoD 完全達成，本步不夾帶 |
| 2026-07-03 | 7 | pbxproj 教訓：新檔 ID 一度誤用 `0060/0061/0062`（實為 MenuBar/Settings/StatusIcon），驗證步驟抓到後改用 `0063/0064/0065` | 往後配置新 ID 前需先 grep 確認未被佔用；UI 檔佔 0060-0062、Utils 佔 0070-0071 |
