#!/bin/bash
# Устанавливает Screenshooter: приложение, скрипт сжатия, автозапуск и папку Inbox.
# Из исходников (нужны Xcode Command Line Tools) или из готового бинарника релиза.
set -euo pipefail
cd "$(dirname "$0")"

LABEL=com.screenshooter.sorter
BIN="$HOME/bin"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INBOX="$HOME/Screenshots/Inbox"

mkdir -p "$BIN" "$INBOX" "$HOME/Library/LaunchAgents"

if command -v brew >/dev/null; then
  brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
  brew list oxipng >/dev/null 2>&1 || brew install oxipng
else
  echo "Homebrew не найден (https://brew.sh): без ffmpeg и oxipng файлы не будут сжиматься." >&2
fi

if [ -f Sources/main.swift ] && xcrun --find swiftc >/dev/null 2>&1; then
  echo "Собираю приложение…"
  xcrun swiftc -O Sources/main.swift -o "$BIN/screenshot-sorter"
elif [ -f screenshot-sorter ]; then
  cp screenshot-sorter "$BIN/screenshot-sorter"
  xattr -d com.apple.quarantine "$BIN/screenshot-sorter" 2>/dev/null || true
else
  echo "Нет ни исходников со swiftc, ни готового бинарника screenshot-sorter." >&2
  exit 1
fi
install -m 755 scripts/screenshot-compress.sh "$BIN/screenshot-compress.sh"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$BIN/screenshot-sorter</string></array>
  <key>WatchPaths</key>
  <array><string>$INBOX</string></array>
  <key>ThrottleInterval</key><integer>2</integer>
  <key>StandardErrorPath</key><string>$HOME/Screenshots/.sorter.log</string>
</dict>
</plist>
PL

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# Скриншоты и записи экрана (Cmd+Shift+3/4/5) — в Inbox.
defaults write com.apple.screencapture location "$INBOX"
killall SystemUIServer 2>/dev/null || true

echo "Готово. Скриншоты сохраняются в $INBOX."
echo "Совет: Cmd+Shift+5 → Параметры → снимите «Показывать плавающую миниатюру», чтобы окно открывалось сразу."
