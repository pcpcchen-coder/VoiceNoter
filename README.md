# VoiceNote

[![Tests](https://github.com/pcpcchen-coder/VoiceNoter/actions/workflows/test.yml/badge.svg)](https://github.com/pcpcchen-coder/VoiceNoter/actions/workflows/test.yml)

macOS 選單列語音筆記 App — 按住熱鍵即錄音，放開即用 WhisperKit 在裝置本地轉成文字。支援繁／簡中文切換、游標位置直接輸入、OpenAI AI 自動校稿，轉錄結果自動追加到當日 Markdown 筆記。

## 功能總覽

- **按住即錄、放開即轉** — 全域熱鍵（預設 `⌥ + Space`），按住錄音、放開自動送 Whisper 轉錄
- **本地 Whisper 語音辨識** — 透過 WhisperKit + CoreML 在 Mac 本地推論，無需上傳音檔
- **多種 Whisper 模型可選** — 從 small (~460 MB) 到 large-v3 完整版 (~3 GB)，可在設定中切換並預先下載
- **模型快取** — 下載過的模型會快取在本地，重啟 App 不需重新下載
- **繁體／簡體中文切換** — 在選單列快速切換，無須進設定頁
- **游標位置直接輸入** — 辨識結果像輸入法一樣自動貼到游標所在位置（可關閉改為僅複製到剪貼簿）
- **AI 自動校稿** — 透過 OpenAI API (gpt-4o-mini) 自動校正轉錄文字（需設定 API Key，可開關）
- **每日 Markdown 筆記** — 轉錄結果自動追加到 `~/Documents/VoiceNotes/YYYY-MM-DD.md`
- **自訂詞表** — 編輯 glossary.txt 提升專有名詞辨識率
- **純選單列 App** — 無 Dock 圖示，不佔空間

## 系統需求

- macOS 14.0 (Sonoma) 以上
- Apple Silicon（arm64）
- Xcode 16.0+ / Swift 5.9+

## 編譯方式

### Xcode

1. 用 Xcode 開啟 `VoiceNote.xcodeproj`
2. 等 Xcode 自動解析 Swift Package（WhisperKit、KeyboardShortcuts）
3. 選 `VoiceNote` scheme，按 `Cmd+R`

### 命令列

```bash
xcodebuild -scheme VoiceNote -configuration Debug build
```

## 跑測試

單元測試涵蓋純邏輯（設定、路徑、筆記格式、繁簡轉換等）。本機執行：

```bash
./scripts/test.sh
```

此腳本與 CI 使用完全相同的指令（`xcodebuild test`）。每次 push 與 pull request 會由
[GitHub Actions](.github/workflows/test.yml) 在 macOS runner 上自動跑測試，結果反映在上方的 Tests badge。

> 涉及真實麥克風、全域熱鍵、WhisperKit 模型、Keychain 的整合面無法用單元測試覆蓋，
> 改由 [`docs/REFACTOR_PLAN.md`](docs/REFACTOR_PLAN.md) 附錄 A 的手動驗收清單把關。

## 第一次啟動

App 啟動後會在選單列出現麥克風圖示（無 Dock 圖示）。

### 權限設定

1. **麥克風權限** — 第一次按熱鍵錄音時系統會詢問，請允許
2. **輔助使用權限** — 全域熱鍵與「游標位置輸入」功能需要 Accessibility 權限。請到「系統設定 → 隱私權與安全性 → 輔助使用」把 VoiceNote 打開

### 模型下載

首次啟動會自動下載 Whisper 模型（預設 `large-v3 turbo`），選單列會顯示下載進度。首次載入模型需要 CoreML 編譯，可能需要數分鐘。

也可以在「設定 → 模型」中預先下載，避免第一次使用時等待。

## 使用方式

### 基本錄音

按住 `⌥ + Space`（Option + Space）即錄音，放開即停止並自動轉錄。

要改熱鍵：選單列點 VoiceNote → **設定…** → **熱鍵**。

### 繁體／簡體中文切換

在選單列 VoiceNote 選單中直接點選「繁體中文」或「簡體中文」，無需開啟設定頁面。

### 輸出方式

預設為「游標位置輸入」模式 — 辨識結果會自動貼到你目前游標所在的位置，像輸入法一樣。

若不需要，可在「設定 → 輸出方式」關閉，改為僅複製到剪貼簿。

### AI 自動校稿

在「設定 → AI 校稿」開啟後，每次轉錄完成會自動透過 OpenAI 校正文字。

需先在「設定 → OpenAI 認證」輸入 API Key。API Key 可在 [OpenAI Platform](https://platform.openai.com/api-keys) 申請。

> **關於游標輸入與校稿的取捨**：為了低延遲，貼到游標位置的是**原始**轉錄文字（不等 AI 校稿）；
> 校稿版本只會更新到當日 Markdown 筆記。因此游標處與筆記內容可能略有出入，這是刻意的設計取捨。

### 語音指令「幫我整理」

轉錄內容包含「幫我整理」或「請整理」時，會把當日筆記全文送 AI 整理，
並以新段落 `## AI 整理 (HH:mm)` **追加**到筆記末尾——原始內容完整保留，不會被覆蓋。
（觸發指令本身不會被寫入筆記。）

## 可選模型

| 模型 | 大小 | 說明 |
|------|------|------|
| `openai_whisper-small` | ~460 MB | 快速，中文尚可 |
| `distil-whisper_distil-large-v3_turbo_600MB` | 600 MB | 輕量快速 |
| `openai_whisper-large-v3_947MB` | 947 MB | 高準確度壓縮版 |
| `openai_whisper-large-v3_turbo_954MB` | 954 MB | 推薦，品質與速度兼顧 |
| `openai_whisper-large-v3_turbo` | ~3 GB | 最佳品質 |
| `openai_whisper-large-v3` | ~3 GB | 最高準確度 |

## 筆記檔位置

- 每日筆記：`~/Documents/VoiceNotes/YYYY-MM-DD.md`
- 詞表：`~/Library/Application Support/VoiceNote/glossary.txt`

筆記格式：

```markdown
# 2026-05-03

## 14:30:12

今天的語音筆記內容
```

## 技術架構

- **SwiftUI** — MenuBarExtra 選單列 App（LSUIElement）
- **WhisperKit** — 本地 CoreML Whisper 語音辨識
- **KeyboardShortcuts** — 全域熱鍵管理
- **OpenAI API** — gpt-4o-mini 文字校稿（Codable + 可注入 URLSession）
- **CGEvent** — 模擬 Cmd+V 實現游標位置輸入
- **ICU StringTransform** — 繁簡中文轉換（Hans-Hant / Hant-Hans）
- **Keychain** — OpenAI API Key 加密儲存

程式碼採依賴注入 + protocol 分層（`Core/` 服務、`UI/` 介面、`Utils/` 工具），
核心流程 `RecordingCoordinator` 全部相依皆可注入 mock，並有完整單元測試。
詳細模組圖、資料流、protocol 清單與測試策略見 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 已知限制

- **游標貼上假設 QWERTY 鍵盤配置**：以 CGEvent 送 Cmd+V 時鍵位寫死，非 QWERTY 硬體配置（如 Dvorak）可能按錯鍵。
- **游標文字未經校稿**：為低延遲，貼到游標的是原始轉錄；AI 校稿版本只更新到筆記檔（見上）。
- **游標輸入需輔助使用權限**：未授權時會自動退回「只複製到剪貼簿」並在選單提示。
- **App Sandbox 關閉**：全域熱鍵與任意路徑寫檔的取捨；要上 Mac App Store 需另做 sandbox。

## 開發文件

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 最終架構、資料流、protocol 清單、測試策略
- [`docs/PROJECT_REVIEW.md`](docs/PROJECT_REVIEW.md) — 重構前的專案檢閱與問題清單
- [`docs/REFACTOR_PLAN.md`](docs/REFACTOR_PLAN.md) — 5 Phase / 14 Step 的分階段 TDD 重構計畫
- [`docs/REFACTOR_PROGRESS.md`](docs/REFACTOR_PROGRESS.md) — 進度追蹤與執行守則

## 授權

見 `LICENSE`。
