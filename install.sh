#!/bin/bash
# Installs Screenshooter: the app, the compression script, the launch agent and the Inbox folder.
# Builds from source (needs Xcode Command Line Tools) or installs the prebuilt release binary.
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
  echo "Homebrew not found (https://brew.sh): without ffmpeg and oxipng files won't be compressed." >&2
fi

if [ -f Sources/main.swift ] && xcrun --find swiftc >/dev/null 2>&1; then
  echo "Building the app…"
  xcrun swiftc -O Sources/*.swift -o "$BIN/screenshot-sorter"
elif [ -f screenshot-sorter ]; then
  cp screenshot-sorter "$BIN/screenshot-sorter"
  xattr -d com.apple.quarantine "$BIN/screenshot-sorter" 2>/dev/null || true
else
  echo "Neither the sources with swiftc nor the prebuilt screenshot-sorter binary were found." >&2
  exit 1
fi
install -m 755 scripts/screenshot-compress.sh "$BIN/screenshot-compress.sh"

# Example categories on first install; edit ~/Screenshots/categories.json to change them.
[ -f "$HOME/Screenshots/categories.json" ] || cp categories.example.json "$HOME/Screenshots/categories.json"

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

# Screenshots and screen recordings (Cmd+Shift+3/4/5) go to Inbox.
defaults write com.apple.screencapture location "$INBOX"
killall SystemUIServer 2>/dev/null || true

echo "Done. Screenshots are saved to $INBOX."
echo "Tip: Cmd+Shift+5 → Options → turn off “Show Floating Thumbnail” so the window opens right away."
