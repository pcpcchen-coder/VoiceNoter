# VoiceNote 架構

> 本文件描述 14 步重構（見 [`REFACTOR_PLAN.md`](./REFACTOR_PLAN.md)）完成後的最終架構。

## 設計原則

- **依賴注入 + protocol**：所有系統邊界（麥克風、WhisperKit、檔案、網路、Keychain、剪貼簿）都藏在 protocol 後面，核心流程只依賴抽象，因此能用 mock 完整單元測試。
- **職責單一**：每個型別一種職責；純邏輯（格式、轉換、判斷）抽成無副作用函式優先測試。
- **狀態單一事實來源**：`AppState` 持有 UI 狀態，`RecorderState` 是狀態機。
- **本地優先、隱私零外傳**：語音轉錄全在本機；只有選用的 AI 校稿會呼叫 OpenAI。

## 模組結構

```
VoiceNote/
├── VoiceNoteApp.swift          # @main：相依組裝 + Scene（無業務邏輯，~49 行）
├── Core/
│   ├── AppState.swift          # @MainActor 狀態容器（state / lastError / infoMessage / 設定鏡射）
│   ├── SettingsStore.swift     # 所有 UserDefaults 存取的唯一入口（含模型路徑快取）
│   ├── RecordingCoordinator.swift   # 流程協調，全 protocol 注入
│   ├── PostTranscriptionPipeline.swift  # 校稿 / 「幫我整理」後處理
│   ├── AudioRecorder.swift     # AudioRecording：AVAudioEngine 16kHz mono
│   ├── HotkeyManager.swift     # KeyboardShortcuts push-to-talk
│   ├── GlossaryStore.swift     # 詞表 bootstrap + initialPrompt
│   ├── Paths.swift             # 路徑常量 + 建目錄
│   ├── Transcription/
│   │   ├── Transcribing.swift          # protocol + DecodingSettings 值型別
│   │   ├── WhisperKitTranscriber.swift # Transcribing 的 WhisperKit 實作
│   │   ├── ModelDownloader.swift       # ModelDownloading：模型下載（暖機/預下載共用）
│   │   └── TranscriptPostProcessor.swift # 純函式：串接/trim/繁簡轉換 + ChineseVariant
│   ├── Notes/
│   │   ├── NoteFormatter.swift  # 純格式（檔名/檔頭/entry/section/取代最後一筆）
│   │   └── NoteStore.swift      # NoteStoring protocol + FileNoteStore
│   ├── AI/
│   │   ├── TextRewriting.swift  # TextRewriting + CredentialProviding protocol
│   │   └── OpenAIRewriter.swift # Codable + 可注入 URLSession + 型別化錯誤
│   ├── Credentials/
│   │   ├── CredentialStore.swift      # CredentialStoring + KeychainCredentialStore + 遷移
│   │   └── CredentialsViewModel.swift # 設定頁認證狀態
│   └── Output/
│       └── TranscriptDeliverer.swift  # TranscriptDelivering + SystemTranscriptDeliverer
├── UI/
│   ├── MenuBarView.swift / MenuStatusText.swift / StatusIcon.swift
│   ├── SettingsView.swift      # 只組裝 7 個 section
│   └── Settings/               # HotkeySection / ModelSection / DecodingSection /
│                               # OutputSection / ProofreadSection / NotesSection /
│                               # AboutSection / ModelDownloadViewModel
└── Utils/
    ├── Logger.swift            # os.Logger
    └── PermissionHelper.swift  # 麥克風 / Accessibility 權限
```

## 核心資料流（錄音一次）

```
熱鍵按下 ─► RecordingCoordinator.handlePress()
             │ 檢查 state（busy/error/idle）→ transcriber.isReady → 麥克風權限
             ▼
          AudioRecording.start()  →  state = .recording
熱鍵放開 ─► handleRelease()  →  state = .transcribing  →  runTranscription()
             │ AudioRecording.stop() → 暫存 wav（太短則丟棄回 idle）
             │ DecodingSettings(settings, prompt: GlossaryStore.prompt())
             │ Transcribing.transcribe() → 文字（含繁簡轉換）
             │ TranscriptDelivering.deliver(text, pasteAtCursor:)  ← B8：無 Accessibility 則只複製
             │ 非「整理」指令 → NoteStoring.append()
             │ state = .idle
             ▼
          PostTranscriptionPipeline
             ├ 一般 + autoProofread → proofread()：rewrite → replaceLastEntry → infoMessage
             └ 「幫我整理」        → organize()：readToday → rewrite → appendSection（不覆蓋）
```

模型暖機與切換：`RecordingCoordinator` 訂閱 `AppState.$selectedModel`，切模型即取消現行暖機、以新模型重載；失敗進 `.error` 狀態（選單顯示「重試模型載入」）。

## Protocol 清單（可注入的邊界）

| Protocol | 正式實作 | 測試替身 |
|----------|----------|----------|
| `AudioRecording` | `AudioRecorder` | `MockAudioRecorder` |
| `Transcribing` | `WhisperKitTranscriber` | `MockTranscriber` |
| `ModelDownloading` | `WhisperKitModelDownloader` | `MockModelDownloader` |
| `NoteStoring` | `FileNoteStore` | `MockNoteStore` |
| `TextRewriting` | `OpenAIRewriter` | `MockRewriter` |
| `CredentialStoring` | `KeychainCredentialStore` | `InMemoryCredentialStore` |
| `TranscriptDelivering` | `SystemTranscriptDeliverer` | `MockDeliverer` |

## 測試策略

- **單元測試（CI 全綠把關）**：設定、路徑、詞表、筆記格式/儲存、繁簡轉換、解碼參數、憑證遷移、AI 校稿（`URLProtocol` stub 不連網）、模型下載 view model、選單文字、以及核心流程 `RecordingCoordinator`（熱鍵門檻、權限、太短、轉錄失敗、校稿/整理、暖機失敗/復原/換模型）。
- **手動驗收（無法單元測試的系統整合面）**：真實麥克風、全域熱鍵、CGEvent 游標貼上、真 Keychain、真 WhisperKit 模型載入。清單見 [`REFACTOR_PLAN.md`](./REFACTOR_PLAN.md) 附錄 A。
- **CI**：GitHub Actions（macOS runner）在每次 push 執行 `xcodebuild test`；本機用 `scripts/test.sh`。WhisperKit 這類系統/簽章相依不在 CI 執行，屬手動驗收。

## 已知限制

- **游標貼上假設 QWERTY**（B7）：以 CGEvent 送 `Cmd+V` 時 virtualKey 寫死 `0x09`（ANSI V 鍵）。非 QWERTY 硬體配置（如 Dvorak）可能按錯鍵。正確修法需 `UCKeyTranslate` 反查鍵位，成本高、影響族群小，暫列為已知限制。
- **游標文字與筆記校稿版可能不一致**（B5，刻意取捨）：為低延遲，游標貼的是原始轉錄；校稿版只更新筆記檔。
- **App Sandbox 關閉**：全域熱鍵與任意路徑寫檔的取捨；要上架 Mac App Store 需另做 sandbox。
