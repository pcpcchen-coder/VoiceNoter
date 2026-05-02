# VoiceNote — Mac 語音碎片筆記 App（Phase 1 規格）

> 給 Claude Code 的實作指令文件。請依本規格從零建立 Xcode 專案，產出可直接 `xcodebuild` 編譯並執行的 macOS App。完成後請印出執行步驟與已知 TODO 清單。

---

## 1. 專案目標

打造一個常駐選單列的 macOS App，按住熱鍵即錄音，放開即用 WhisperKit 在本地轉成文字，自動：
1. 追加到當日 Markdown 筆記檔
2. 複製到剪貼簿
3. 在選單列顯示最近一筆轉錄結果預覽

**設計原則**：本地優先、隱私零外傳、低延遲、不打擾使用者目前在做的事。

---

## 2. 技術規格

| 項目 | 規格 |
|---|---|
| 平台 | macOS 14.0+ (Sonoma) |
| 架構 | Apple Silicon 優先（arm64） |
| 語言 | Swift 5.9+ |
| UI | SwiftUI + MenuBarExtra |
| App 類型 | `LSUIElement = true`（無 Dock 圖示、純選單列） |
| Bundle ID | `com.george.voicenote` |
| 最低 Xcode | 15.0+ |

### 套件依賴（Swift Package Manager）

```
WhisperKit         https://github.com/argmaxinc/WhisperKit         (from: "0.9.0")
KeyboardShortcuts  https://github.com/sindresorhus/KeyboardShortcuts (from: "2.0.0")
```

不要引入其他第三方套件。

---

## 3. 功能需求（Phase 1 範圍）

### 3.1 核心錄音流程
- **熱鍵**：預設 `⌥ + Space`（Option + Space），使用 `KeyboardShortcuts` 套件，使用者可在設定面板重綁
- **互動模式**：按住錄音（push-to-talk）。按下開始錄、放開立即停止並送轉錄
- **錄音格式**：16 kHz、單聲道、Float32 PCM；存成暫存 `.wav`，轉錄完即刪
- **錄音引擎**：`AVAudioEngine` + `installTap` 即時抓取 buffer
- **錄音時長上限**：60 秒（超過自動停止並轉錄，避免記憶體炸開）
- **最短錄音**：< 0.3 秒視為誤觸，丟棄不轉錄

### 3.2 轉錄
- **引擎**：WhisperKit
- **預設模型**：`large-v3-turbo`（首次啟動自動下載到 `~/Documents/huggingface/models`，下載期間選單列顯示 spinner）
- **語言**：強制 `zh`（中文）
- **prompt 注入**：把 `~/Library/Application Support/VoiceNote/glossary.txt` 內容（每行一個詞）以逗號串接後當 `initialPrompt` 餵入，提升專有名詞辨識
- **首次啟動的 glossary.txt 預設內容**（請程式碼中以資源檔形式提供，第一次啟動寫到 Application Support）：
  ```
  EMS
  能源管理系統
  電池
  換電站
  PCS
  CATL
  寧德時代
  虛擬電廠
  VPP
  儲能
  ```

### 3.3 輸出
- **Markdown 落檔**：`~/Documents/VoiceNotes/YYYY-MM-DD.md`
  - 檔不存在時自動建立，第一行寫 `# YYYY-MM-DD\n`
  - 每筆追加格式：
    ```
    ## HH:MM:SS
    
    {轉錄文字}
    
    ```
- **剪貼簿**：轉錄完成立即把純文字寫入 `NSPasteboard.general`
- **選單列預覽**：選單下拉選項首列顯示「最近：{前 30 字}…」，點擊可開啟當日 md 檔（用預設 app）

### 3.4 選單列 UI（MenuBarExtra）
選單列圖示用 SF Symbol：
- 待機：`mic`
- 錄音中：`mic.fill`（紅色 tint）
- 轉錄中：`waveform`（旋轉動畫或 ProgressView）
- 模型下載中：`arrow.down.circle`

選單下拉內容（由上而下）：
1. 狀態文字（例如「待機中 · 熱鍵 ⌥Space」）
2. 最近一筆預覽（可點擊 → 開啟今日 md）
3. ─── 分隔線 ───
4. 「開啟今日筆記」 → Finder 顯示 `YYYY-MM-DD.md`
5. 「開啟筆記資料夾」 → Finder 開啟 `~/Documents/VoiceNotes/`
6. 「設定…」 → 開啟設定視窗
7. ─── 分隔線 ───
8. 「結束 VoiceNote」

### 3.5 設定視窗（SwiftUI Window）
極簡，包含：
- 熱鍵綁定欄位（用 `KeyboardShortcuts.Recorder`）
- 模型選擇下拉：`tiny` / `base` / `small` / `medium` / `large-v3` / `large-v3-turbo`（變更後提示「重啟生效」）
- 筆記儲存路徑顯示 + 「在 Finder 顯示」按鈕
- glossary.txt 編輯按鈕（用預設編輯器開啟）
- 版本資訊

### 3.6 錯誤處理
- 麥克風權限被拒：選單列圖示變灰，下拉顯示「麥克風權限未授予 → 開啟系統設定」（點擊跳到對應的隱私設定頁）
- 模型下載失敗：選單顯示錯誤訊息 + 「重試」按鈕
- 轉錄失敗：把錯誤寫到 log，選單顯示「上次轉錄失敗」紅字一次（下次錄音清掉）

---

## 4. 專案結構

```
VoiceNote/
├── VoiceNote.xcodeproj
├── VoiceNote/
│   ├── VoiceNoteApp.swift              # @main, MenuBarExtra 進入點
│   ├── Info.plist
│   ├── VoiceNote.entitlements
│   ├── Resources/
│   │   └── default_glossary.txt        # 內建詞表，首次啟動複製到 Application Support
│   ├── Core/
│   │   ├── AppState.swift              # ObservableObject，全域狀態（idle/recording/transcribing/error）
│   │   ├── AudioRecorder.swift         # AVAudioEngine 包裝
│   │   ├── TranscriptionService.swift  # WhisperKit 包裝
│   │   ├── NoteWriter.swift            # 寫 Markdown + 剪貼簿
│   │   ├── HotkeyManager.swift         # KeyboardShortcuts 整合
│   │   └── Paths.swift                 # 統一管理檔案路徑
│   ├── UI/
│   │   ├── MenuBarView.swift           # 選單下拉內容
│   │   ├── SettingsView.swift          # 設定視窗
│   │   └── StatusIcon.swift            # 動態 SF Symbol 圖示
│   └── Utils/
│       ├── Logger.swift                # OSLog 包裝
│       └── PermissionHelper.swift      # 麥克風/Accessibility 權限檢查
└── README.md
```

---

## 5. 各模組實作規格

### 5.1 `AppState.swift`
```swift
enum RecorderState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case error(String)
    case downloadingModel(progress: Double)
}

@MainActor
final class AppState: ObservableObject {
    @Published var state: RecorderState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastError: String? = nil
    static let shared = AppState()
}
```

### 5.2 `AudioRecorder.swift`
- 用 `AVAudioEngine` + `inputNode.installTap(onBus:0, bufferSize:1024, format:nil)`
- 把 buffer 轉成 16kHz mono Float32（用 `AVAudioConverter`），累積到一個 `[Float]` array
- 提供 `start()` / `stop() async -> URL`（回傳暫存 wav 檔路徑）
- 暫存路徑：`FileManager.default.temporaryDirectory.appendingPathComponent("voicenote-\(UUID()).wav")`
- 用 `AVAudioFile` 寫成 wav

### 5.3 `TranscriptionService.swift`
```swift
final class TranscriptionService {
    private var whisperKit: WhisperKit?
    
    func warmup(modelName: String) async throws  // App 啟動時呼叫
    func transcribe(audioURL: URL, prompt: String?) async throws -> String
}
```
- 用 `WhisperKit(model: modelName, download: true)` 初始化
- 下載進度透過 closure 回拋給 AppState
- 轉錄參數：`language: "zh"`、`task: .transcribe`、`temperature: 0.0`、`initialPrompt: prompt`
- 回傳結果做 `.trimmingCharacters(in: .whitespacesAndNewlines)`

### 5.4 `NoteWriter.swift`
```swift
struct NoteWriter {
    static func append(transcript: String, at: Date = Date()) throws -> URL
    static func copyToPasteboard(_ text: String)
    static func todayNoteURL() -> URL
}
```
- 路徑用 `Paths.notesDirectory`
- 寫檔用 `FileHandle` append 模式，避免重讀整個檔
- 用 `DateFormatter`（`yyyy-MM-dd` / `HH:mm:ss`）

### 5.5 `HotkeyManager.swift`
- 用 sindresorhus 的 `KeyboardShortcuts` 套件
- 定義一個 shortcut name：
  ```swift
  extension KeyboardShortcuts.Name {
      static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: [.option]))
  }
  ```
- 監聽 keyDown / keyUp 兩種事件（這套件支援 `onKeyDown` / `onKeyUp`），分別觸發 start / stop

### 5.6 `Paths.swift`
```swift
enum Paths {
    static var notesDirectory: URL  // ~/Documents/VoiceNotes/
    static var appSupportDirectory: URL  // ~/Library/Application Support/VoiceNote/
    static var glossaryFile: URL  // appSupportDirectory + glossary.txt
    static func ensureDirectoriesExist()
    static func bootstrapGlossaryIfNeeded()  // 首次啟動從 bundle 複製 default_glossary.txt
}
```

### 5.7 `VoiceNoteApp.swift`
```swift
@main
struct VoiceNoteApp: App {
    @StateObject private var state = AppState.shared
    
    init() {
        Paths.ensureDirectoriesExist()
        Paths.bootstrapGlossaryIfNeeded()
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            StatusIcon(state: state.state)
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
```

App 啟動時要：
1. 呼叫 `Paths` 初始化
2. 啟動 background Task 預熱 WhisperKit（讀使用者選的模型）
3. 註冊熱鍵 keyDown / keyUp handler
4. 檢查麥克風權限（未決定時不主動請求，等第一次按熱鍵才觸發）

---

## 6. Info.plist 必要欄位

```xml
<key>LSUIElement</key>
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>VoiceNote 需要麥克風權限來錄製你的語音筆記。所有轉錄都在本機進行，不會上傳到雲端。</string>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

## 7. Entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- 全域熱鍵 + 任意路徑寫檔需要 -->
<key>com.apple.security.device.audio-input</key>
<true/>
```

> 註：App Sandbox 關閉是 Phase 1 的取捨。要上 Mac App Store 才需要 sandbox + 對應的 user-selected file 權限，那是後話。

---

## 8. 實作順序（給 Claude Code 的執行步驟）

依以下順序逐步建立並驗證，每步都要能編譯通過再進下一步：

1. **建立 Xcode 專案**：`File > New > Project > macOS > App`，SwiftUI + Swift，命名 VoiceNote
2. **設定 Bundle ID、`LSUIElement`、Info.plist 權限字串、entitlements**
3. **加入 SPM 依賴**：WhisperKit、KeyboardShortcuts
4. **建立 `Paths.swift`、`Logger.swift`**（最底層，無依賴）
5. **建立 `AppState.swift`**
6. **建立 `StatusIcon.swift`**（純 UI，可先用假狀態驗證選單列顯示）
7. **跑起來確認選單列圖示正常顯示**
8. **建立 `AudioRecorder.swift`** + 寫一個 debug menu item「測試錄 3 秒」驗證能存出 wav
9. **建立 `TranscriptionService.swift`** + 把測試按鈕串起來：錄 3 秒 → 轉文字 → print 到 console
10. **建立 `NoteWriter.swift`**，把上一步的結果寫進 md 檔 + 剪貼簿
11. **建立 `HotkeyManager.swift`**，把測試按鈕換成全域熱鍵觸發
12. **建立 `MenuBarView.swift`** 完整選單
13. **建立 `SettingsView.swift`**
14. **錯誤處理 + 權限引導**
15. **寫 README.md**：怎麼編譯、第一次啟動會跳哪些權限、怎麼換熱鍵

---

## 9. README.md 內容要求

請產出一份 README.md 包含：
- 一句話介紹
- 系統需求（macOS 14、Apple Silicon）
- 編譯方式（`xcodebuild` 指令 + Xcode 開啟）
- 第一次啟動會跳的權限說明（麥克風、Accessibility）
- 預設熱鍵 + 怎麼改
- 筆記檔位置
- 已知限制（Phase 1 沒做的：VAD 自動分段、片段管理視窗、Notion 整合、tag 系統）
- 後續 Phase 2/3 的 roadmap 簡述

---

## 10. 驗收條件（DoD）

完成後執行以下流程應全部通過：
1. `xcodebuild -scheme VoiceNote build` 不報錯
2. App 啟動後選單列出現麥克風圖示、無 Dock 圖示
3. 第一次按熱鍵跳出系統麥克風權限請求，授予後可錄音
4. 按住 `⌥ + Space` 講「測試一二三」，放開後 3 秒內：
   - 選單列圖示變化過 idle → recording → transcribing → idle
   - `~/Documents/VoiceNotes/YYYY-MM-DD.md` 多一筆紀錄
   - 剪貼簿內容是「測試一二三」（或近似）
   - 選單下拉「最近：」顯示這句話前 30 字
5. 點選「開啟今日筆記」會用預設 app 打開 md 檔
6. 設定視窗能成功改熱鍵且立即生效
7. 模型首次下載期間選單圖示為 `arrow.down.circle`，下載完自動切回 idle

---

## 11. 不在 Phase 1 範圍（請勿提前實作，但程式碼結構應預留擴充空間）

- VAD 自動分段
- 片段時間軸主視窗、編輯、重新轉錄
- Tag 系統（idea / todo / spec）
- 自動貼到當前游標位置
- 跨日語意搜尋
- Notion / Apple Notes 匯出
- AI 後處理（送 Claude/Kimi 整理）
- 中英雙語自動偵測（目前強制 zh）

---

## 12. 編碼風格要求

- 全部用 `async/await`，避免 callback hell
- 跨 thread 的狀態更新一律 `@MainActor`
- 所有 IO 錯誤往上拋，最頂層在 `AppState` 統一轉成 `.error(String)` 顯示
- 用 `os.Logger`（subsystem: `com.george.voicenote`），不要用 `print` 留在正式程式碼
- 中文註解可，但 API 命名一律英文
- SwiftUI View 不超過 150 行，超過就拆子 view

---

**請依本規格產出完整可編譯專案，並在最後印出：**
1. 你建立的所有檔案清單
2. 第一次跑起來的步驟（指令 + 預期權限彈窗順序）
3. 已知 TODO 或你做了哪些規格外的合理決定
