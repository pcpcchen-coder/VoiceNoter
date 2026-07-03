# VoiceNote 重構計畫（分階段 + TDD）

> 本計畫依 [`PROJECT_REVIEW.md`](./PROJECT_REVIEW.md) 的問題清單設計，共 **5 個 Phase、14 個 Step**。
> 每個 Step 都是獨立可完成的最小單位：**先寫測試（紅）→ 實作（綠）→ 整理（重構）**，
> 完成後專案必須能編譯、全部測試通過、App 行為不變（除該 Step 明確列出的修正）。
>
> **使用方式**：對 Claude 說「請完成 Step N」即可。執行規則見 [`REFACTOR_PROGRESS.md`](./REFACTOR_PROGRESS.md)。

---

## 階段總覽

| Phase | Step | 標題 | 解決問題 | 規模 |
|-------|------|------|----------|------|
| **0 地基** | 1 | 建立 CI 與測試基準線 | T3 | S |
| **1 純邏輯抽取** | 2 | `SettingsStore`：設定集中化與可注入 | A3, T2 | M |
| | 3 | `TranscriptPostProcessor`：繁簡轉換純函式化 | A5(部分) | S |
| | 4 | `NoteWriter` 拆分：`NoteFormatter` + `NoteStore` + 系統動作 | A4, B4(基礎) | M |
| | 5 | `GlossaryStore`：詞表模組化 | A5(部分) | S |
| **2 服務協定化** | 6 | `Transcribing` 協定與模型快取集中 | A2, A5, A8(部分) | M |
| | 7 | `OpenAIRewriter` 重構：Codable + 可注入 + 型別化錯誤 | A2, T4 | M |
| | 8 | `CredentialStore`：API Key 移入 Keychain | S1 | M |
| | 9 | 死碼大掃除：OAuth 流程、重複頁面、print | D1–D5, S2, B6 | S |
| **3 核心流程重組** | 10 | `RecordingCoordinator` 獨立化與全依賴注入 | A1, A2, T1, T4 | L |
| | 11 | `PostTranscriptionPipeline`：校稿/整理流程重構與 bug 修正 | B1–B5 | L |
| **4 狀態與 UI** | 12 | `RecorderState` 收斂 + 模型切換免重啟 | D3, A9 | M |
| | 13 | `SettingsView` 拆分 + `ModelDownloader` 統一 | A6, A8 | M |
| **5 收尾** | 14 | 文件同步、最終清掃、手動驗收 | A7, B7–B9(記錄或修) | S |

規模：S = 半天內、M = 半天到一天、L = 一天以上（含測試撰寫）。

### 相依關係

```
Step 1 ──► 之後所有 Step 都以「CI 綠燈」為驗收
Step 2 ──► Step 6（模型快取 key 集中）、Step 10（設定注入）
Step 3 ──► Step 6（轉錄服務瘦身後只依賴後處理器）
Step 4 ──► Step 11（校稿用 NoteStore.replaceLastEntry）
Step 6, 7 ──► Step 10, 11（Coordinator/Pipeline 注入用的 protocol）
Step 7 ──► Step 8（憑證讀取走 CredentialProviding）
Step 8 ──► Step 9（新路徑就緒後才刪舊碼）
Step 10 ──► Step 11, 12
```

**原則上請依編號順序執行**。跳過執行前，先確認上表相依已滿足。

### 最終目標結構

```
VoiceNote/
├── VoiceNoteApp.swift              # 只剩 App 進入點與依賴組裝（< 80 行）
├── Core/
│   ├── AppState.swift              # 純狀態容器，可注入建構
│   ├── SettingsStore.swift         # 所有 UserDefaults 存取的唯一入口
│   ├── RecordingCoordinator.swift  # 流程協調，全 protocol 相依
│   ├── PostTranscriptionPipeline.swift  # 校稿/整理流程
│   ├── AudioRecorder.swift         # (+ AudioRecording protocol)
│   ├── HotkeyManager.swift
│   ├── Paths.swift                 # 只管路徑
│   ├── GlossaryStore.swift
│   ├── Transcription/
│   │   ├── Transcribing.swift      # protocol + DecodingSettings
│   │   ├── WhisperKitTranscriber.swift
│   │   ├── TranscriptPostProcessor.swift
│   │   └── ModelDownloader.swift
│   ├── Notes/
│   │   ├── NoteFormatter.swift     # 純格式邏輯
│   │   └── NoteStore.swift         # NoteStoring protocol + FileNoteStore
│   ├── AI/
│   │   ├── TextRewriting.swift     # protocol
│   │   └── OpenAIRewriter.swift
│   ├── Credentials/
│   │   └── CredentialStore.swift   # CredentialStoring protocol + Keychain 實作
│   └── Output/
│       └── TranscriptDeliverer.swift  # 剪貼簿 / 游標貼上
├── UI/
│   ├── MenuBarView.swift
│   ├── StatusIcon.swift
│   └── Settings/                   # SettingsView 拆分後的子 view
└── Utils/
    ├── Logger.swift
    └── PermissionHelper.swift

VoiceNoteTests/                      # 每個 Core 型別對應一個測試檔 + Mocks/
```

---

## 通用規則（每個 Step 都適用）

### TDD 節奏

1. **紅**：先在 `VoiceNoteTests/` 新增該 Step 規格中列出的測試案例，確認編譯失敗或測試失敗。
2. **綠**：以最小實作讓測試通過。
3. **重構**：整理命名與重複，再跑一次全部測試。

### 驗收條件（每個 Step 的共同 DoD）

- [ ] `xcodebuild test -project VoiceNote.xcodeproj -scheme VoiceNote -destination 'platform=macOS'` 全綠（本機或 CI）。
- [ ] 該 Step 規格中列出的新測試全部存在且通過。
- [ ] App 可正常啟動、錄音、轉錄（涉及流程變動的 Step 需做手動 smoke test，見 §附錄）。
- [ ] 未夾帶其他 Step 的變更。
- [ ] 更新 [`REFACTOR_PROGRESS.md`](./REFACTOR_PROGRESS.md) 的進度表。
- [ ] Commit 訊息格式：`Step N: <標題>`。

### 環境限制說明

WhisperKit 需要下載模型且依賴 CoreML，**單元測試一律不碰真模型**——WhisperKit adapter 屬「薄封裝」，
由手動驗收覆蓋；其餘邏輯全部以 mock 測試。Claude 的遠端環境（Linux）無法執行 `xcodebuild`，
因此 Step 1 先建 CI，之後每個 Step 由 CI（或使用者本機）驗證測試結果。

---

# Phase 0 — 地基

## Step 1：建立 CI 與測試基準線

**解決問題**：T3（無 CI、改壞無警報）。之後所有 Step 的 DoD 都依賴本步驟。

**前置**：無。

### TDD / 測試

本步驟不新增產品程式碼，「測試」就是讓現有 3 個測試檔在 CI 上跑起來：

- 確認 `VoiceNote.xcscheme` 的 Test action 包含 `VoiceNoteTests`（已存在則不動）。
- CI 上全部現有測試（AppStateTests、PathsTests、NoteWriterTests）通過。

### 任務

1. 新增 `.github/workflows/test.yml`：
   - 觸發：`push` 到所有分支、`pull_request`。
   - Runner：`macos-15`（Xcode 16.x）。
   - 步驟:checkout → 快取 SPM（`~/Library/Developer/Xcode/DerivedData` 或 `-clonedSourcePackagesDirPath` 指定目錄）→
     `xcodebuild test -project VoiceNote.xcodeproj -scheme VoiceNote -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`。
2. 新增 `scripts/test.sh`：把上面那行指令包成一鍵腳本，本機與 CI 共用。
3. README 加上 CI badge 與「跑測試」章節。

### 檔案異動

- 新增：`.github/workflows/test.yml`、`scripts/test.sh`
- 修改：`README.md`

### DoD（本步驟專屬）

- [ ] CI 在此分支跑出綠燈（含現有 3 個測試檔）。
- [ ] 本機執行 `scripts/test.sh` 與 CI 行為一致。

**風險**：私有 repo 的 macOS runner 分鐘數以 10 倍計費（GitHub Free 每月 2000 分鐘 → 折合 200 macOS 分鐘）。
若額度吃緊，備案是保留 `scripts/test.sh`、CI 改為只在 PR 觸發，或完全以本機驗證取代（DoD 改為附上本機測試輸出）。

---

# Phase 1 — 純邏輯抽取（低風險、高測試價值）

## Step 2：`SettingsStore` — 設定集中化與可注入

**解決問題**：A3（UserDefaults 散落、遷移邏輯藏在屬性初始化）、T2（singleton 測試汙染）。

**前置**：Step 1。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/SettingsStoreTests.swift`，用 `UserDefaults(suiteName: UUID().uuidString)` 隔離：

- `test_selectedModel_defaultsToLargeV3Turbo`
- `test_selectedModel_persistsAcrossInstances`
- `test_migration_mapsAllLegacyModelNames`（表驅動：`tiny`→`openai_whisper-small` … 共 8 組映射）
- `test_migration_writesBackMigratedName`（讀取後 defaults 內已是新名稱）
- `test_migration_leavesUnknownNamesUntouched`
- `test_autoProofread_defaultsToFalse`
- `test_chineseVariant_defaultsToTraditional`
- `test_pasteAtCursor_defaultsToTrue`
- `test_decodingParameters_defaults`（topK=5、temperature=0.0、fallbackCount=5）
- 各設定的 set → get round-trip

改寫 `AppStateTests`：改用 `AppState(settings: SettingsStore(defaults: 隔離 suite))` 新建實例，不再碰 `AppState.shared`（T2）。

### 任務

1. 新增 `Core/SettingsStore.swift`：
   - `final class SettingsStore`，`init(defaults: UserDefaults = .standard)`。
   - 集中所有 key 為 `private enum Key: String`（`selectedModel`、`autoProofread`、`chineseVariant`、`pasteAtCursor`、`decodingTopK`、`decodingTemperature`、`decodingFallbackCount`）。
   - 型別化屬性（get/set 直通 defaults），預設值與現行為完全一致。
   - 模型名稱遷移表由 `AppState` 搬入，於 `selectedModel` 的 getter 觸發（讀到舊名 → 回寫新名並回傳新名）。
2. `AppState` 改為 `init(settings: SettingsStore = SettingsStore())`（`internal`，不再 `private`）：
   - `@Published` 屬性初始值改由 `settings` 讀取；各 `setXxx` 方法改為寫入 `settings` 後更新 `@Published`。
   - 保留 `static let shared = AppState()` 供 App 使用。
3. 全案搜尋 `UserDefaults.standard`，除 `SettingsStore` 與「模型路徑快取」（Step 6 處理）、「OAuth token」（Step 8 處理）外不得殘留。

### 檔案異動

- 新增：`Core/SettingsStore.swift`、`VoiceNoteTests/SettingsStoreTests.swift`
- 修改：`Core/AppState.swift`、`VoiceNoteTests/AppStateTests.swift`

### DoD（本步驟專屬）

- [ ] `AppState` 內無任何 UserDefaults 字面量 key。
- [ ] `AppStateTests` 不再引用 `AppState.shared`。

---

## Step 3：`TranscriptPostProcessor` — 繁簡轉換純函式化

**解決問題**：A5（轉錄服務混雜後處理）。

**前置**：Step 1。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/TranscriptPostProcessorTests.swift`：

- `test_process_convertsSimplifiedToTraditional`（`"语音转录"` → `"語音轉錄"`）
- `test_process_convertsTraditionalToSimplified`
- `test_process_trimsWhitespaceAndNewlines`
- `test_process_joinsMultipleSegmentsWithSpace`
- `test_process_returnsNilForEmptyResult`（全空白 segments → nil）
- `test_chineseVariant_rawValuesMatchLegacyStrings`（`"zh-Hant"` / `"zh-Hans"`，確保 UserDefaults 相容）

### 任務

1. 新增 `Core/Transcription/TranscriptPostProcessor.swift`：
   ```swift
   enum ChineseVariant: String, CaseIterable {
       case traditional = "zh-Hant"
       case simplified  = "zh-Hans"
   }

   enum TranscriptPostProcessor {
       /// segments 串接 → trim → 空則 nil → 繁簡轉換
       static func process(segments: [String], variant: ChineseVariant) -> String?
   }
   ```
2. `TranscriptionService.transcribe` 內的 join/trim/empty 判斷/`StringTransform` 全部改呼叫上述函式。
3. `SettingsStore.chineseVariant` 與 `AppState.chineseVariant` 升級為 `ChineseVariant` 型別（raw value 存取保持相容）；`MenuBarView` 跟著改。

### 檔案異動

- 新增：`Core/Transcription/TranscriptPostProcessor.swift`、`VoiceNoteTests/TranscriptPostProcessorTests.swift`
- 修改：`Core/TranscriptionService.swift`、`Core/SettingsStore.swift`、`Core/AppState.swift`、`UI/MenuBarView.swift`

### DoD（本步驟專屬）

- [ ] `TranscriptionService` 內不再出現 `StringTransform` 與繁簡字串常量。
- [ ] 專案中 `"zh-Hant"` / `"zh-Hans"` 字面量只存在於 `ChineseVariant` 定義。

---

## Step 4：`NoteWriter` 拆分 — `NoteFormatter` + `NoteStore` + 系統動作

**解決問題**：A4（四種職責混雜）、為 B4 修復鋪路（提供可靠的 `replaceLastEntry`）。

**前置**：Step 1。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/NoteFormatterTests.swift`（純函式，無 IO）：

- `test_fileName_isYYYYMMDD`
- `test_header_isH1WithDate`
- `test_entry_formatsTimeHeadingAndBody`
- `test_replacingLastOccurrence_replacesOnlyLastMatch`（同字句出現兩次，只換最後一次）
- `test_replacingLastOccurrence_returnsNilWhenNotFound`
- `test_replacingLastOccurrence_handlesUnicode`

新增 `VoiceNoteTests/FileNoteStoreTests.swift`（temp 目錄 IO，沿用現有 `NoteWriterTests` 全部案例改名遷入）：

- 現有 6 個案例（todayNoteURL / 建檔含 header / 二次 append / 跨日分檔 / 自動建目錄 / Unicode）
- `test_replaceLastEntry_rewritesLastMatchOnDisk`
- `test_replaceLastEntry_throwsWhenOriginalNotFound`（明確拋錯，不再靜默）

### 任務

1. 新增 `Core/Notes/NoteFormatter.swift`：`fileName(for:)`、`header(for:)`、`entry(transcript:at:)`、
   `replacingLastOccurrence(of:with:in:) -> String?`（純函式；`DateFormatter` 由 `NoteWriter` 搬入）。
2. 新增 `Core/Notes/NoteStore.swift`：
   ```swift
   protocol NoteStoring {
       func append(transcript: String, at date: Date) throws -> URL
       func todayNoteURL(now: Date) -> URL
       func readToday(now: Date) throws -> String
       func replaceLastEntry(matching original: String, with replacement: String, now: Date) throws
   }
   final class FileNoteStore: NoteStoring { init(directory: URL = Paths.notesDirectory) }
   ```
   檔案 IO 從 `NoteWriter` 遷入，格式一律呼叫 `NoteFormatter`。
3. 新增 `Core/Output/TranscriptDeliverer.swift`：`copyToPasteboard` / `pasteAtCursor`（CGEvent）/ `openInDefaultApp` 由 `NoteWriter` 遷入（先做具體型別，protocol 化留給 Step 10）。
4. 更新呼叫端（`MenuBarView`、`RecordingCoordinator`），**刪除 `NoteWriter.swift` 與 `NoteWriterTests.swift`**（案例已遷移）。

### 檔案異動

- 新增：`Core/Notes/NoteFormatter.swift`、`Core/Notes/NoteStore.swift`、`Core/Output/TranscriptDeliverer.swift`、對應兩個測試檔
- 修改：`UI/MenuBarView.swift`、`VoiceNoteApp.swift`
- 刪除：`Core/NoteWriter.swift`、`VoiceNoteTests/NoteWriterTests.swift`

### DoD（本步驟專屬）

- [ ] 筆記輸出格式與重構前 byte-for-byte 相同（由遷移的既有測試保證）。
- [ ] `replaceLastEntry` 失敗會拋錯（為 Step 11 修 B4 做準備）。

---

## Step 5：`GlossaryStore` — 詞表模組化

**解決問題**：A5 的一部分（`Paths` 兼職 glossary 讀取與 bootstrap）。

**前置**：Step 1。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/GlossaryStoreTests.swift`（自 `PathsTests` 遷入 4 個 glossary 案例，另加）：

- `test_prompt_returnsCommaJoinedTerms` / `skipsBlankLines` / `nilForMissingFile` / `nilForEmptyFile`（遷入）
- `test_bootstrap_copiesBundledDefaultWhenMissing`
- `test_bootstrap_doesNotOverwriteExistingFile`

### 任務

1. 新增 `Core/GlossaryStore.swift`：
   ```swift
   struct GlossaryStore {
       // 註（Step 5 實作）：改用 defaultSource: URL? 注入而非 bundle: Bundle，
       // 以便測試直接注入 temp 來源檔，避免在 macOS 偽造 bundle 資源查找。
       init(fileURL: URL = Paths.glossaryFile,
            defaultSource: URL? = Bundle.main.url(forResource: "default_glossary", withExtension: "txt"))
       func bootstrapIfNeeded()
       func prompt() -> String?   // 逗號串接的 initialPrompt
   }
   ```
   邏輯自 `Paths.bootstrapGlossaryIfNeeded()` / `readGlossaryAsPrompt(from:)` 遷入。
2. `Paths` 只保留路徑常量與 `ensureDirectoriesExist()`；`PathsTests` 同步瘦身。
3. 呼叫端（`VoiceNoteApp.init`、`runTranscription`）改用 `GlossaryStore`。

### 檔案異動

- 新增：`Core/GlossaryStore.swift`、`VoiceNoteTests/GlossaryStoreTests.swift`
- 修改：`Core/Paths.swift`、`VoiceNoteTests/PathsTests.swift`、`VoiceNoteApp.swift`

### DoD（本步驟專屬）

- [ ] `Paths` 內不再有檔案內容讀寫（只剩路徑與建目錄）。

---

# Phase 2 — 服務層協定化

## Step 6：`Transcribing` 協定與模型快取集中

**解決問題**：A2/A5（轉錄服務不可替換）、A8 的快取 key 重複、T4。

**前置**：Step 2（SettingsStore）、Step 3（後處理器）。

### TDD / 測試（先寫）

- `VoiceNoteTests/Mocks/MockTranscriber.swift`：可設定回傳文字/拋錯/記錄呼叫參數的 mock（供本步及 Step 10+ 使用）。
- `SettingsStoreTests` 追加：
  - `test_modelFolderPath_roundTrip`
  - `test_modelFolderPath_isNamespacedPerModel`（兩個模型互不干擾）
- 新增 `VoiceNoteTests/DecodingSettingsTests.swift`：
  - `test_defaults_matchLegacyValues`（language=zh、topK=5、temperature=0、fallback=5）
  - `test_init_fromSettingsStore`（從 SettingsStore 組出 DecodingSettings）

### 任務

1. 新增 `Core/Transcription/Transcribing.swift`：
   ```swift
   struct DecodingSettings: Equatable {
       var language = "zh"
       var topK = 5
       var temperature: Float = 0
       var temperatureFallbackCount = 5
       var prompt: String?
       var variant: ChineseVariant = .traditional
       init(settings: SettingsStore, prompt: String?)  // 便利建構
   }

   protocol Transcribing: AnyObject {
       var isReady: Bool { get }
       func warmup(modelName: String,
                   onProgress: @MainActor @escaping (Double) -> Void,
                   onLoadingStarted: @MainActor @escaping () -> Void) async throws
       func transcribe(audioURL: URL, settings: DecodingSettings) async throws -> String
   }
   ```
2. `TranscriptionService` 更名 `WhisperKitTranscriber`（檔案移到 `Core/Transcription/`），conform `Transcribing`；
   6 參數的 `transcribe` 簽名收斂成 `DecodingSettings`。
3. 模型路徑快取（`whisperkit_model_path_` 前綴）從 `WhisperKitTranscriber` 與 `SettingsView` 移入
   `SettingsStore.modelFolderPath(for:)` / `setModelFolderPath(_:for:)` — 全案只剩一處 key 組字。
4. `RecordingCoordinator` 持有型別改為 `Transcribing`。

### 檔案異動

- 新增：`Core/Transcription/Transcribing.swift`、`VoiceNoteTests/Mocks/MockTranscriber.swift`、`VoiceNoteTests/DecodingSettingsTests.swift`
- 修改/搬移：`Core/TranscriptionService.swift` → `Core/Transcription/WhisperKitTranscriber.swift`、`Core/SettingsStore.swift`、`UI/SettingsView.swift`、`VoiceNoteApp.swift`

### DoD（本步驟專屬）

- [ ] `grep -r "whisperkit_model_path" VoiceNote/` 只命中 `SettingsStore.swift`。
- [ ] WhisperKit import 只存在於 `WhisperKitTranscriber.swift` 與 `SettingsView.swift`（後者 Step 13 處理）。

---

## Step 7：`OpenAIRewriter` 重構 — Codable + 可注入 + 型別化錯誤

**解決問題**：A2/T4（AIRewriter 不可測）、為 Step 11 提供 mock 點。

**前置**：Step 1。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/OpenAIRewriterTests.swift`，以 `URLProtocol` stub 攔截網路：

- `test_rewrite_throwsMissingAPIKey_whenNoCredential`（且不發出任何請求）
- `test_rewrite_buildsCorrectRequest`（URL、`Authorization: Bearer`、model=gpt-4o-mini、system+user messages、temperature）
- `test_rewrite_parsesSuccessResponse`（回傳 content 並 trim）
- `test_rewrite_mapsHTTPErrorWithServerMessage`（401 + error.message → `.http(status:message:)`）
- `test_rewrite_throwsDecodingFailed_onMalformedJSON`

### 任務

1. 新增 `Core/AI/TextRewriting.swift`：
   ```swift
   protocol TextRewriting {
       func rewrite(_ text: String) async throws -> String
   }
   protocol CredentialProviding {
       var apiKey: String? { get }
   }
   ```
2. 新增 `Core/AI/OpenAIRewriter.swift`（取代 `Core/AIRewriter.swift`）：
   - `init(credentials: CredentialProviding, session: URLSession = .shared, model: String = "gpt-4o-mini")`
   - Request/Response 用 `Codable` struct，去掉 `JSONSerialization` 與 `[String: Any]`。
   - `enum OpenAIRewriterError: LocalizedError`：`missingAPIKey`、`http(status: Int, message: String)`、`decodingFailed`。
   - 目前的 system prompt 與參數（max_tokens 2048、temperature 0.5）原樣保留。
3. 過渡期讓 `OpenAIOAuthManager` conform `CredentialProviding`（Step 8 換成 Keychain 實作）。
4. 呼叫端（coordinator 內兩處 `AIRewriter.rewrite`）改用注入的 `TextRewriting` 實例。刪除 `AIRewriter.swift`。

### 檔案異動

- 新增：`Core/AI/TextRewriting.swift`、`Core/AI/OpenAIRewriter.swift`、`VoiceNoteTests/OpenAIRewriterTests.swift`、`VoiceNoteTests/Mocks/MockRewriter.swift`
- 修改：`VoiceNoteApp.swift`、`OpenAIOAuthManager.swift`
- 刪除：`Core/AIRewriter.swift`

### DoD（本步驟專屬）

- [ ] 專案內無 `JSONSerialization`。
- [ ] Rewriter 測試不需網路即可全綠。

---

## Step 8：`CredentialStore` — API Key 移入 Keychain

**解決問題**：S1（明文儲存）。

**前置**：Step 7（`CredentialProviding` 已存在）。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/CredentialMigrationTests.swift` + `VoiceNoteTests/Mocks/InMemoryCredentialStore.swift`：

- `test_migration_movesLegacyTokenFromDefaultsToStore`（隔離 defaults 有舊 token → 遷移後 store 有值、defaults 已清空）
- `test_migration_skipsWhenNoLegacyToken`
- `test_migration_doesNotOverwriteExistingStoreValue`
- `test_inMemoryStore_setGetClearRoundTrip`
-（可選，本機跑）`KeychainCredentialStoreTests`：真 Keychain round-trip，標 `XCTSkip` 於 CI 無簽章環境。

### 任務

1. 新增 `Core/Credentials/CredentialStore.swift`：
   ```swift
   protocol CredentialStoring: CredentialProviding, AnyObject {
       func set(_ apiKey: String?) throws
       func clear() throws
   }
   final class KeychainCredentialStore: CredentialStoring {
       // kSecClassGenericPassword, service: "com.george.voicenote", account: "openai_api_key"
   }
   ```
2. 一次性遷移函式（獨立、可測）：
   `migrateLegacyToken(defaults: UserDefaults, into store: CredentialStoring)` —
   從 `openai_access_token` / `openai_refresh_token` 讀出、寫入 store、`removeObject` 舊 key。App 啟動時呼叫。
3. 新增 `UI/Settings` 用的 `CredentialsViewModel: ObservableObject`（包 `CredentialStoring`，發布「已認證/未認證」），
   `SettingsView` 的認證區塊改走它（儲存/清除/狀態顯示）。
4. `OpenAIRewriter` 的 `credentials` 注入改為 `KeychainCredentialStore`。

### 檔案異動

- 新增：`Core/Credentials/CredentialStore.swift`、`Core/Credentials/CredentialsViewModel.swift`、兩個測試檔、一個 mock
- 修改：`UI/SettingsView.swift`、`VoiceNoteApp.swift`

### DoD（本步驟專屬）

- [ ] 新輸入的 API Key 只存在 Keychain（可用「鑰匙圈存取」App 驗證）。
- [ ] 舊版使用者升級後 key 自動遷移、功能不中斷。
- [ ] UserDefaults plist 中不再出現 token。

---

## Step 9：死碼大掃除

**解決問題**：D1（OpenAISettingsView）、D2（OAuth 流程）、D4（無人呼叫 API）、D5/S2（print）、B6（handleAPIError 一併刪除）。

**前置**：Step 8（新憑證路徑已上線，舊管理器可整檔刪除）。

### TDD / 測試

刪除型步驟，不新增測試；以「全案編譯 + 既有測試全綠 + grep 檢查」驗收。

### 任務

1. **刪除整檔**：`OpenAISettingsView.swift`、`OpenAIOAuthManager.swift`
   （OAuth 流程 UI 早已 disabled 且 OpenAI 不開放第三方 OAuth 註冊；憑證功能已由 Step 8 取代。
   `SettingsView` 內「OpenAI 網頁登入 (OAuth)」整個 Section 與 `autoReauthOn401` Toggle 一併移除）。
2. 刪除無人呼叫的 API：`AudioRecorder.cancel()`、`AudioRecorder.currentDuration`
   （若未來要做「Esc 取消錄音」再以 TDD 重新加回；`revealInFinder` 若 Step 4 後仍殘留一併刪）。
3. `grep -rn "print(" VoiceNote/` 歸零（Preview/debug 除外，正式碼一律改 `Log`）。

### 檔案異動

- 刪除：`OpenAISettingsView.swift`、`OpenAIOAuthManager.swift`
- 修改：`UI/SettingsView.swift`、`Core/AudioRecorder.swift`

### DoD（本步驟專屬）

- [ ] `grep -rn "print(" VoiceNote/ --include=*.swift` 無正式碼命中。
- [ ] 不再有 `ASWebAuthenticationSession` / `AuthenticationServices` import。

---

# Phase 3 — 核心流程重組

## Step 10：`RecordingCoordinator` 獨立化與全依賴注入

**解決問題**：A1（god object 與進入點同檔）、A2/T1/T4（核心流程 0 覆蓋）。**本步驟不改行為**，只搬家 + 注入 + 補測試。

**前置**：Step 4（NoteStoring）、Step 6（Transcribing）、Step 7（TextRewriting）。

### TDD / 測試（先寫）

新增 mocks：`MockAudioRecorder`（可注入 stop 回傳的 URL 或拋 `tooShort`）、`MockDeliverer`、（沿用 `MockTranscriber`、`MockNoteStore`、`MockRewriter`）。

新增 `VoiceNoteTests/RecordingCoordinatorTests.swift`（`@MainActor`，AppState 用 Step 2 的隔離建構）：

- `test_press_whenModelNotReady_showsWaitMessage_andDoesNotStartRecorder`
- `test_press_whenModelLoadFailed_showsRetryMessage`
- `test_press_whenMicDenied_showsPermissionMessage`
- `test_press_whenAuthorized_startsRecorder_andEntersRecordingState`
- `test_press_whileBusy_isIgnored`（recording/transcribing/downloading 各一）
- `test_release_transcribes_appendsNote_andDelivers`（驗證 glossary prompt 有帶入、deliverer 收到轉錄文字、note append 內容正確、state 回 idle）
- `test_release_deliveryRespectsPasteAtCursorSetting`（true → paste、false → 只複製）
- `test_release_tooShortRecording_returnsToIdle_writesNothing`
- `test_release_transcriptionFailure_setsLastError`
- `test_release_withoutRecording_isNoop`

### 任務

1. 新增 `protocol AudioRecording`（`start() throws` / `stop() async throws -> URL`），`AudioRecorder` conform。
2. `Core/Output/TranscriptDeliverer.swift` 補上 `protocol TranscriptDelivering { func deliver(_ text: String, pasteAtCursor: Bool) }`，
   現有具體實作更名 `SystemTranscriptDeliverer`。
3. `RecordingCoordinator` 搬到 `Core/RecordingCoordinator.swift`，建構子改為全注入：
   ```swift
   init(state: AppState,
        settings: SettingsStore,
        recorder: AudioRecording,
        transcriber: Transcribing,
        noteStore: NoteStoring,
        rewriter: TextRewriting,
        deliverer: TranscriptDelivering,
        glossary: GlossaryStore)
   ```
   `handlePress()` / `handleRelease()` 改 `internal` 供測試呼叫。
   註（Step 10 實作）：init 改為純儲存相依（無副作用）；掛熱鍵與 `scheduleWarmup` 移到 `activate()`，由 `VoiceNoteApp` 於組裝後呼叫。避免暖機 Task 與單元測試斷言競態。另加 `waitForPendingWork()` 供測試 await 轉錄 Task。
4. `VoiceNoteApp.swift` 剩：進入點、依賴組裝（production 實例）、Scene 定義。
5. 校稿/「幫我整理」邏輯**原樣搬移**（含既有 bug，Step 11 才修），但改走注入的 `rewriter` 與 `noteStore`。

### 檔案異動

- 新增：`Core/RecordingCoordinator.swift`、`VoiceNoteTests/RecordingCoordinatorTests.swift`、`VoiceNoteTests/Mocks/`（recorder / deliverer / note store）
- 修改：`VoiceNoteApp.swift`（大幅瘦身）、`Core/AudioRecorder.swift`、`Core/Output/TranscriptDeliverer.swift`

### DoD（本步驟專屬）

- [ ] `VoiceNoteApp.swift` < 100 行、不含業務邏輯。
- [ ] 上列 10 個流程測試全綠（不碰真麥克風/真模型/真網路）。
- [ ] 手動 smoke test：熱鍵錄音→轉錄→貼上→筆記，行為與重構前一致。

---

## Step 11：`PostTranscriptionPipeline` — 校稿/整理流程重構與 bug 修正

**解決問題**：B1（成功訊息走錯誤通道）、B2（訊息立即被清除）、B3（整檔覆蓋資料遺失）、B4（字串手術 + 靜默失敗）、B5（游標貼上與筆記不一致——以文件化決策處理）。

**前置**：Step 10。

### 行為決策（本步驟的規格，實作前先確認）

1. **訊息分級**：`AppState` 新增 `@Published var infoMessage: String?`（灰字資訊），`lastError` 只留給錯誤（紅字）。下一次錄音開始時兩者都清除。
2. **校稿**：完成後用 `NoteStore.replaceLastEntry`（Step 4，會拋錯）更新筆記；失敗設 `lastError`，成功設 `infoMessage = "已自動校稿"`。
   游標貼上仍用原始轉錄文字（低延遲優先），筆記以校稿後為準——此取捨寫入 README（B5 的處理）。
3. **「幫我整理」**：
   - 觸發語句**不寫入**筆記（偵測到指令就不 append）。
   - 整理結果以**新段落** `## AI 整理 (HH:mm)` 追加到當日筆記**末尾**，永不覆蓋原始內容（B3 的資料遺失修復）。
   - 進行中設 `infoMessage = "AI 整理中…"`，完成改為 `"筆記已由 AI 整理"`。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/PostTranscriptionPipelineTests.swift`（全 mock）：

- `test_detectOrganizeCommand_matchesTriggerPhrases`（「幫我整理」「請整理」；一般語句不觸發）
- `test_proofread_replacesLastEntry_andSetsInfoMessage`
- `test_proofread_failure_setsLastError_keepsOriginalNote`
- `test_proofread_disabled_doesNothing`
- `test_organize_appendsSummarySection_preservesOriginalContent`
- `test_organize_triggerUtterance_isNotAppendedToNote`
- `test_organize_failure_setsLastError`
- `test_infoMessage_isNotClearedByPipelineCompletion`（回歸鎖 B2）

`RecordingCoordinatorTests` 追加：

- `test_newRecording_clearsInfoMessageAndLastError`

### 任務

1. 新增 `Core/PostTranscriptionPipeline.swift`：自 coordinator 抽出校稿與整理，依賴 `TextRewriting` + `NoteStoring` + `AppState`；
   `detectOrganizeCommand(_:) -> Bool` 為純函式。
2. `AppState`：加 `infoMessage`；`noteSoftFailure` 不再被成功路徑呼叫；刪除 `runTranscription` 尾端整段清錯誤的順序問題（B2）。
3. `MenuBarView`：`infoMessage` 以 `.secondary` 灰字顯示、`lastError` 維持紅字。
4. Coordinator 的 `runTranscription` 收斂為：stop → transcribe → deliver → （偵測整理指令分流）→ pipeline。

### 檔案異動

- 新增：`Core/PostTranscriptionPipeline.swift`、`VoiceNoteTests/PostTranscriptionPipelineTests.swift`
- 修改：`Core/RecordingCoordinator.swift`、`Core/AppState.swift`、`UI/MenuBarView.swift`、`VoiceNoteTests/AppStateTests.swift`、`README.md`（B5 取捨說明）

### DoD（本步驟專屬）

- [ ] B1–B4 各有至少一個回歸測試鎖住。
- [ ] 手動驗收：開啟校稿講一句話 → 選單出現灰字「已自動校稿」、筆記內容被校稿版取代；說「幫我整理」→ 原筆記完整保留、末尾多出 AI 整理段落。

---

# Phase 4 — 狀態與 UI

## Step 12：`RecorderState` 收斂 + 模型切換免重啟

**解決問題**：D3（`.error` 死狀態）、A9（切模型要重啟）。

**前置**：Step 10。

### 行為決策

- `.error` 不刪除，改為**真正使用**：模型載入失敗屬 hard error → 進 `.error`，取代 coordinator 的 `modelLoadFailed: Bool`（狀態機單一事實來源）。`StatusIcon` 的 error 外觀已存在，順勢啟用。
- 設定中切換模型後**即時重載**：取消現行暖機、以新模型重新 `warmup`；期間熱鍵按下顯示「模型載入中」。移除「重啟生效」提示文字。

### TDD / 測試（先寫）

- `RecordingCoordinatorTests` 追加：
  - `test_warmupFailure_entersErrorState`（取代原 modelLoadFailed 測試）
  - `test_retryWarmup_fromErrorState_recovers`
  - `test_modelChange_cancelsAndRestartsWarmup_withNewModelName`（MockTranscriber 記錄 warmup 呼叫序列）
  - `test_press_duringModelReload_isBlockedWithMessage`
- 新增 `VoiceNoteTests/MenuStatusTextTests.swift`：把 `MenuBarView.statusLine` 抽成純函式 `MenuStatusText.line(state:hotkeyDescription:)` 後，逐狀態驗證文案。

### 任務

1. Coordinator：刪 `modelLoadFailed`，warmup 失敗 → `state.setError(...)`；`retryWarmup` 從 `.error` 恢復；
   以 Combine 訂閱 `AppState.$selectedModel`（或 `SettingsStore` 通知）觸發重載。
2. `MenuBarView`：`重試模型載入` 按鈕改由 `case .error` 驅動；`statusLine` 抽到 `UI/MenuStatusText.swift`。
3. `SettingsView`：移除「變更後請重啟」文案，改為「切換後自動重新載入模型」。

### 檔案異動

- 新增：`UI/MenuStatusText.swift`、`VoiceNoteTests/MenuStatusTextTests.swift`
- 修改：`Core/RecordingCoordinator.swift`、`Core/AppState.swift`、`UI/MenuBarView.swift`、`UI/SettingsView.swift`

### DoD（本步驟專屬）

- [ ] 手動驗收：設定頁切換模型 → 選單列進入下載/載入狀態 → 完成後直接可用新模型，全程不重啟。
- [ ] `AppState.setError` 有生產呼叫端，D3 除名。

---

## Step 13：`SettingsView` 拆分 + `ModelDownloader` 統一

**解決問題**：A6（243 行巨型 View）、A8（下載邏輯重複）。

**前置**：Step 6（快取已集中）、Step 12（重啟提示已改）。

### TDD / 測試（先寫）

新增 `VoiceNoteTests/ModelDownloadViewModelTests.swift`（注入 mock downloader）：

- `test_download_publishesProgressUpdates`
- `test_download_success_recordsPathInSettings_andShowsDoneMessage`
- `test_download_failure_showsErrorMessage_andAllowsRetry`
- `test_download_preventsConcurrentDownloads`

### 任務

1. 新增 `Core/Transcription/ModelDownloader.swift`：
   `protocol ModelDownloading { func download(variant: String, progress: @escaping (Double) -> Void) async throws -> URL }` +
   WhisperKit 實作。`WhisperKitTranscriber.warmup` 與設定頁預下載共用它（A8 收斂完成）。
2. 新增 `UI/Settings/ModelDownloadViewModel.swift`（`ObservableObject`，狀態機：idle/downloading/done/failed）。
3. `SettingsView` 拆成 `UI/Settings/` 下的子 view，每檔 ≤ 150 行：
   `HotkeySection` / `ModelSection`（含下載 UI）/ `DecodingSection` / `OutputSection` / `ProofreadSection`（含認證）/ `NotesSection` / `AboutSection`；
   `SettingsView` 只剩組裝。
4. `SettingsView` 對 WhisperKit 的直接 import 移除（統一走 `ModelDownloading`）。

### 檔案異動

- 新增：`Core/Transcription/ModelDownloader.swift`、`UI/Settings/`（7 個子 view + view model）、兩個測試/mock 檔
- 修改：`UI/SettingsView.swift`、`Core/Transcription/WhisperKitTranscriber.swift`

### DoD（本步驟專屬）

- [ ] `UI/` 下沒有任何單檔 View 超過 150 行。
- [ ] `import WhisperKit` 只剩 `WhisperKitTranscriber.swift` 與 `ModelDownloader.swift`。

---

# Phase 5 — 收尾

## Step 14：文件同步、最終清掃、手動驗收

**解決問題**：A7（檔案歸位收尾）、B7/B8/B9（修復或文件化）、整體一致性。

**前置**：Step 1–13。

### 任務

1. **小修或文件化**（每項擇一，預設建議如下）：
   - B8（貼上前未檢查 Accessibility）：**修**——`SystemTranscriptDeliverer.pasteAtCursor` 前檢查 `PermissionHelper.isAccessibilityGranted()`，未授權則 fallback 複製 + `infoMessage` 提示開權限（附測試）。
   - B9（權限狀態不即時）：**修**——選單開啟時呼叫 `refreshMicPermission()`。
   - B7（virtualKey 0x09 非 QWERTY 問題）：**文件化**為已知限制（正確修法需 UCKeyTranslate 反查鍵位，成本高、影響族群小）。
2. `VoiceNote_Phase1_Spec.md` 移到 `docs/history/`（歷史文件，標注已被本計畫取代）。
3. README「技術架構」章節改寫為最終結構；補「已知限制」章節。
4. 新增 `docs/ARCHITECTURE.md`：最終模組圖、資料流、protocol 清單、測試策略（哪些靠單元測試、哪些靠手動驗收）。
5. 全案最終檢查：`print` 歸零、無 TODO 殘留、資料夾與 Xcode group 一致、`REFACTOR_PROGRESS.md` 全部打勾。
6. 跑完整手動驗收清單（附錄 A），結果記錄進 progress 文件。

### DoD（本步驟專屬）

- [ ] 附錄 A 手動驗收全數通過。
- [ ] 文件（README / ARCHITECTURE / PROGRESS）與程式碼一致。

---

# 附錄 A — 手動驗收清單（Phase 3、4 後與 Step 14 執行）

單元測試無法覆蓋系統整合面（真麥克風、全域熱鍵、CGEvent、Keychain、WhisperKit），需在 Mac 上人工執行：

1. [ ] 冷啟動：選單列出現麥克風圖示、無 Dock 圖示；首次啟動自動下載模型並顯示進度。
2. [ ] 按住 `⌥Space` 說「測試一二三」放開 → 3 秒內：圖示走過 recording → transcribing → idle；游標處貼出文字；當日 md 多一筆。
3. [ ] 設定關閉「游標輸入」→ 只進剪貼簿。
4. [ ] 繁／簡切換後轉錄結果字形正確。
5. [ ] 錄音 < 0.3 秒 → 無輸出、無錯誤紅字。
6. [ ] 設定頁切換模型 → 不重啟直接生效（Step 12 後）。
7. [ ] 開啟 AI 校稿 + 有效 API Key → 筆記被校稿版取代、選單灰字「已自動校稿」（Step 11 後）。
8. [ ] 說「幫我整理」→ 原筆記完好、末尾出現「## AI 整理」段落（Step 11 後）。
9. [ ] API Key 儲存後在「鑰匙圈存取」可見、UserDefaults plist 無 token（Step 8 後）。
10. [ ] 拔掉麥克風權限（系統設定關閉）→ 圖示變 `mic.slash`、選單引導開設定。
11. [ ] 錄音滿 60 秒自動停止並轉錄。
12. [ ] 熱鍵重綁後立即生效。
