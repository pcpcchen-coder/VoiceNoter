# VoiceNote 專案檢閱報告

> 檢閱日期：2026-07-03
> 檢閱範圍：`main` 分支全部原始碼（15 個 Swift 檔，共 1,742 行）、3 個測試檔、Xcode 專案設定
> 本報告是 [`REFACTOR_PLAN.md`](./REFACTOR_PLAN.md) 的依據，計畫中的每個 Step 都會引用此處的問題編號。

---

## 1. 專案概觀

VoiceNote 是一個 macOS 選單列語音筆記 App：按住熱鍵錄音、放開後用 WhisperKit 在本地轉錄，
結果自動貼到游標位置／剪貼簿、追加到當日 Markdown 筆記，並可選用 OpenAI 自動校稿。

| 項目 | 現況 |
|------|------|
| 平台 | macOS 14+，Apple Silicon |
| UI | SwiftUI `MenuBarExtra`（`LSUIElement`，無 Dock 圖示） |
| 相依套件 | WhisperKit（>= 0.9.0）、KeyboardShortcuts（>= 2.0.0） |
| 測試 | XCTest，3 個測試檔（AppState / Paths / NoteWriter），無 CI |
| 沙盒 | 關閉（全域熱鍵與任意路徑寫檔需要，屬刻意取捨） |

### 1.1 現有檔案結構

```
VoiceNote/
├── VoiceNoteApp.swift          # ⚠️ 253 行：App 進入點 + RecordingCoordinator（核心流程全在這）
├── OpenAIOAuthManager.swift    # ⚠️ 264 行：放在根層，混合 API Key 儲存與死掉的 OAuth 流程
├── OpenAISettingsView.swift    # ⚠️ 死碼：無任何地方引用
├── Core/
│   ├── AppState.swift          # 全域狀態 singleton，UserDefaults 讀寫散落其中
│   ├── AudioRecorder.swift     # AVAudioEngine 錄音（品質尚可）
│   ├── TranscriptionService.swift  # WhisperKit 封裝 + 下載快取 + 繁簡轉換（三種職責）
│   ├── NoteWriter.swift        # Markdown 格式 + 檔案 IO + 剪貼簿 + CGEvent 貼上（四種職責）
│   ├── AIRewriter.swift        # OpenAI 校稿 API（JSONSerialization、不可注入、不可測）
│   ├── HotkeyManager.swift     # KeyboardShortcuts 封裝（乾淨）
│   └── Paths.swift             # 路徑管理 + glossary 讀取（兩種職責）
├── UI/
│   ├── MenuBarView.swift       # 選單內容
│   ├── SettingsView.swift      # ⚠️ 243 行，違反自訂規範（View ≤ 150 行），內含模型下載邏輯
│   └── StatusIcon.swift        # 狀態圖示（乾淨）
└── Utils/
    ├── Logger.swift            # os.Logger 封裝（乾淨）
    └── PermissionHelper.swift  # 麥克風/Accessibility 權限（乾淨）
```

### 1.2 核心流程（現況）

```
熱鍵按下 ──► RecordingCoordinator.handlePress()
                │  檢查狀態 / 模型就緒 / 麥克風權限
                ▼
             AudioRecorder.start() ──► state = .recording
熱鍵放開 ──► handleRelease() ──► runTranscription()
                │ recorder.stop() → 暫存 wav
                │ TranscriptionService.transcribe()（含繁簡轉換）
                │ NoteWriter.pasteAtCursor() 或 copyToPasteboard()
                │ NoteWriter.append() → 當日 md
                │ [autoProofread 開啟] AIRewriter.rewrite() → 字串手術改寫筆記檔
                │ [語句含「幫我整理」] AIRewriter.rewrite(整份筆記) → 整檔覆蓋
                ▼
             state = .idle
```

---

## 2. 問題清單

每個問題有唯一編號，重構計畫中以編號引用。嚴重度：🔴 高（bug/安全）、🟡 中（架構/可維護性）、🟢 低（風格/清理）。

### A. 架構問題

| 編號 | 嚴重度 | 問題 | 位置 |
|------|--------|------|------|
| A1 | 🟡 | `RecordingCoordinator` 是 god object：熱鍵、模型暖機、錄音、轉錄、輸出、AI 校稿、「幫我整理」全部混在一起，且與 App 進入點同檔 | `VoiceNoteApp.swift:39-253` |
| A2 | 🟡 | 全部相依皆為具體類別（`AudioRecorder`、`TranscriptionService`、`NoteWriter`、`AIRewriter`），無 protocol、無依賴注入 → 核心流程完全無法單元測試 | 全專案 |
| A3 | 🟡 | 設定儲存散落：`AppState` 內 8 個 UserDefaults key 字串直接散落；模型名稱遷移邏輯藏在屬性初始化中（有寫入副作用） | `AppState.swift:30-57` |
| A4 | 🟡 | `NoteWriter` 混雜四種職責：Markdown 格式、檔案 IO、剪貼簿、CGEvent 貼上、NSWorkspace 開檔 | `NoteWriter.swift` |
| A5 | 🟡 | `TranscriptionService` 混雜三種職責：WhisperKit 封裝、模型下載快取（UserDefaults）、繁簡轉換後處理 | `TranscriptionService.swift` |
| A6 | 🟡 | `SettingsView` 243 行，違反專案自訂規範「SwiftUI View 不超過 150 行」（spec §12） | `SettingsView.swift` |
| A7 | 🟢 | 檔案位置不一致：`OpenAIOAuthManager.swift`、`OpenAISettingsView.swift` 在專案根層而非 Core/UI | 專案根層 |
| A8 | 🟡 | 模型下載邏輯重複實作兩次：`SettingsView.downloadSelectedModel()` 與 `TranscriptionService.warmup()` 各自下載 + 各自組 `whisperkit_model_path_` 快取 key | `SettingsView.swift:203-225`、`TranscriptionService.swift:29-57` |
| A9 | 🟢 | 模型切換需重啟 App 才生效（Coordinator 未觀察 `selectedModel` 變更） | `SettingsView.swift:58` |

### B. 正確性 Bug

| 編號 | 嚴重度 | 問題 | 位置 |
|------|--------|------|------|
| B1 | 🔴 | 成功訊息走錯誤通道：校稿完成呼叫 `noteSoftFailure("語音已自動校稿")`、整理完成呼叫 `noteSoftFailure("筆記內容已由 AI 整理")` — 成功訊息以紅色錯誤字顯示 | `VoiceNoteApp.swift:226,239` |
| B2 | 🔴 | 校稿成功訊息設定後立即被 `state.lastError = nil`（`runTranscription` 尾端）清除 → 使用者永遠看不到 | `VoiceNoteApp.swift:248` |
| B3 | 🔴 | 「幫我整理」指令將 AI 回覆**整檔覆蓋**當日筆記：原始內容與標題結構全數遺失、觸發語句本身先被寫入筆記、非同步 Task 與後續錄音有 race condition | `VoiceNoteApp.swift:232-245` |
| B4 | 🔴 | 校稿後改寫筆記檔用 `range(of:options:.backwards)` 字串手術 + `try?` 靜默吞錯，同字句出現多次時可能改錯位置 | `VoiceNoteApp.swift:220-224` |
| B5 | 🟡 | `pasteAtCursor` 貼出的是**未校稿**文字（校稿只改筆記檔），游標處與筆記內容不一致 | `VoiceNoteApp.swift:209-214` |
| B6 | 🟡 | `OpenAIOAuthManager.handleAPIError` 判斷邏輯錯誤（`NSURLErrorDomain` 沒有 code 401；把 `userInfo` 的 description 當 Int 取），且從未被呼叫 | `OpenAIOAuthManager.swift:226-257` |
| B7 | 🟢 | CGEvent 貼上寫死 virtualKey `0x09`（ANSI 配置的 V 鍵），非 QWERTY 鍵盤配置（如 Dvorak）會按錯鍵 | `NoteWriter.swift:68` |
| B8 | 🟢 | `pasteAtCursor` 前未檢查 Accessibility 權限，無權限時靜默失敗（文字仍在剪貼簿，但使用者不知道發生什麼事） | `NoteWriter.swift:62-76` |
| B9 | 🟢 | `micPermission` 只在啟動與請求後刷新；使用者中途在系統設定變更權限不會反映到選單列 | `AppState.swift:121-123` |

### S. 安全問題

| 編號 | 嚴重度 | 問題 | 位置 |
|------|--------|------|------|
| S1 | 🔴 | OpenAI API Key 以**明文**存放在 UserDefaults（plist 檔任何程式可讀）→ 應改用 Keychain | `OpenAIOAuthManager.swift:179-184` |
| S2 | 🟢 | 認證流程大量 `print` 到 stdout，違反專案規範「用 os.Logger，不要 print」（spec §12） | `OpenAIOAuthManager.swift` 全檔 |

### T. 測試問題

| 編號 | 嚴重度 | 問題 | 位置 |
|------|--------|------|------|
| T1 | 🟡 | 覆蓋率極低：只有 AppState / Paths / NoteWriter 的純邏輯有測試；錄音→轉錄→輸出的核心流程 0 覆蓋 | `VoiceNoteTests/` |
| T2 | 🟡 | `AppStateTests` 直接操作 `AppState.shared` singleton — 測試間相互汙染、順序相依 | `AppStateTests.swift` |
| T3 | 🟡 | 無 CI、無一鍵測試指令；改壞東西不會有任何警報 | — |
| T4 | 🟡 | `TranscriptionService` / `AIRewriter` / `RecordingCoordinator` 因具體相依完全不可測（A2 的後果） | — |

### D. 死碼與風格

| 編號 | 嚴重度 | 問題 | 位置 |
|------|--------|------|------|
| D1 | 🟢 | `OpenAISettingsView.swift` 整檔死碼：無任何地方引用（功能已被 `SettingsView` 內建區塊取代），檔案首行還殘留 AI 產物註解 | `OpenAISettingsView.swift` |
| D2 | 🟢 | OAuth 整段流程為死碼：UI 已 disabled 並標注「尚未開放」，`login` / `exchangeCodeForToken` / `makeAuthURL` / `ensureLoginIfNeeded` / `handleAPIError` 無人呼叫或不可達 | `OpenAIOAuthManager.swift` |
| D3 | 🟢 | `AppState.setError` 只有測試在呼叫；`RecorderState.error` 狀態生產程式幾乎不會進入 | `AppState.swift:65` |
| D4 | 🟢 | 無人呼叫的 API：`NoteWriter.revealInFinder`、`AudioRecorder.cancel()`、`AudioRecorder.currentDuration` | 各檔 |
| D5 | 🟢 | `print` 殘留於正式程式碼（同 S2） | `OpenAIOAuthManager.swift` |

---

## 3. 做得好的部分（重構時保留）

- `AudioRecorder`：格式轉換、chunk 寫檔、audio queue 上的 snapshot 避免 race，都寫得謹慎。
- `HotkeyManager` / `Logger` / `PermissionHelper` / `StatusIcon`：小而專注，職責單一。
- `NoteWriter.append` / `Paths.readGlossaryAsPrompt` 已有 `directory:` / `from:` 參數注入，是專案裡少數可測的設計，現有測試也寫得不錯（值得作為全專案的測試風格範本）。
- 錯誤區分 hard error（`setError`）與 soft failure（`noteSoftFailure`）的**概念**是對的，只是實作與使用出了問題（B1/B2/D3）。
- 模型名稱遷移（舊名 → WhisperKit 變體名）考慮到了升級相容性。

---

## 4. 重構總體目標

1. **可測試性**：核心流程（錄音→轉錄→輸出→筆記）以 protocol + 依賴注入解耦，用 mock 完整覆蓋。
2. **修正已知 bug**：B1–B5 全數修復，並用測試鎖住。
3. **安全**：API Key 移入 Keychain（S1）。
4. **職責單一**：每個型別一種職責；純邏輯（格式、轉換、判斷）抽成無副作用函式優先測試。
5. **刪除死碼**：D1–D5 清空。
6. **不改變使用者可見行為**（除明確列出的 bug 修正與體驗改善），每個 Step 完成後 App 都能正常編譯執行。

具體步驟見 [`REFACTOR_PLAN.md`](./REFACTOR_PLAN.md)，進度見 [`REFACTOR_PROGRESS.md`](./REFACTOR_PROGRESS.md)。
