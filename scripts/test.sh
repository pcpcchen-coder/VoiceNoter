#!/usr/bin/env bash
#
# VoiceNote 單元測試腳本 — 本機與 CI 共用。
#
# 用法：
#   ./scripts/test.sh
#
# 環境變數（可選）：
#   DESTINATION   xcodebuild 目標平台，預設 "platform=macOS"
#
# 需求：macOS + Xcode 16（含 Swift Package 解析）。
# 若安裝了 xcbeautify 會自動美化輸出，否則使用原始 xcodebuild 輸出。

set -euo pipefail

# 切換到專案根目錄（腳本位於 scripts/ 之下）。
cd "$(dirname "$0")/.."

PROJECT="VoiceNote.xcodeproj"
SCHEME="VoiceNote"
DESTINATION="${DESTINATION:-platform=macOS}"

# -clonedSourcePackagesDirPath 讓 SPM 相依集中到可快取的目錄。
# CODE_SIGNING_ALLOWED=NO 讓沒有簽章憑證的 CI 環境也能編譯與測試。
ARGS=(
  test
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -clonedSourcePackagesDirPath .spm-cache
  CODE_SIGNING_ALLOWED=NO
)

echo "▶︎ xcodebuild ${ARGS[*]}"

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "${ARGS[@]}" | xcbeautify
else
  xcodebuild "${ARGS[@]}"
fi
