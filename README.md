# VoiceNote

按住熱鍵即錄音、放開即用 WhisperKit 在本地轉成文字的 macOS 選單列 App。轉錄結果會自動追加到當日的 Markdown 筆記檔，並複製到剪貼簿。

## 系統需求

- macOS 14.0 (Sonoma) 以上
- Apple Silicon（arm64）優先
- Xcode 15.0+ / Swift 5.9+

## 編譯方式

### Xcode

1. 用 Xcode 開啟 `VoiceNote.xcodeproj`
2. 等 Xcode 自動解析 Swift Package（WhisperKit、KeyboardShortcuts）
3. 選 `VoiceNote` scheme，按 `Cmd+R`

### 命令列

```bash
xcodebuild -scheme VoiceNote -configuration Debug build
```

或用 `xcodebuild -resolvePackageDependencies` 預先抓套件。

## 第一次啟動

App 啟動後會在選單列出現麥克風圖示（無 Dock 圖示）。第一次按熱鍵錄音時會跳出系統權限：

1. **麥克風權限**：第一次按 `⌥ + Space` 時系統會詢問，請允許
2. （首次啟動）**Whisper 模型下載**：選單列圖示會切到 `arrow.down.circle`，模型存在 `~/Documents/huggingface/models`，下載完自動切回 `mic`

> 全域熱鍵需要 Accessibility 權限。若 macOS 跳出 Accessibility 提示，請到「系統設定 → 隱私權與安全性 → 輔助使用」把 VoiceNote 打開。

## 預設熱鍵

按住 `⌥ + Space`（Option + Space）即錄音、放開即送轉錄。

要改熱鍵：選單列點 VoiceNote → **設定…** → **熱鍵** 區塊重綁。

## 筆記檔位置

- 每日筆記：`~/Documents/VoiceNotes/YYYY-MM-DD.md`
- 詞表（用於提升專有名詞辨識）：`~/Library/Application Support/VoiceNote/glossary.txt`

格式：

```markdown
# 2026-05-02

## 14:30:12

測試一二三
```

## Phase 1 已知限制

以下功能不在 Phase 1 範圍：

- VAD 自動分段
- 片段管理 / 編輯 / 重新轉錄
- Tag 系統（idea / todo / spec）
- 自動貼到當前游標位置
- 跨日語意搜尋
- Notion / Apple Notes 匯出
- AI 後處理（送 Claude/Kimi 整理）
- 中英雙語自動偵測（目前強制 `zh`）

## Roadmap

- **Phase 2**：VAD 分段、片段管理視窗、tag、跨日搜尋
- **Phase 3**：Notion/Apple Notes 整合、AI 後處理 pipeline、雙語偵測

## 授權

見 `LICENSE`。
