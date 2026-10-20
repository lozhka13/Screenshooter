#!/bin/bash
# Installs Screenshooter from source: builds Screenshooter.app, copies it to Applications and opens it.
# On first launch the app sets up ~/Screenshots/Inbox, the screenshot location and its launch agent.
set -euo pipefail
cd "$(dirname "$0")"

if command -v brew >/dev/null; then
  brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
  brew list oxipng >/dev/null 2>&1 || brew install oxipng
else
  echo "Homebrew not found (https://brew.sh): without ffmpeg and oxipng files won't be compressed." >&2
fi

scripts/build-app.sh

# /Applications when writable (admin accounts), otherwise ~/Applications.
TARGET=/Applications
[ -w "$TARGET" ] || TARGET="$HOME/Applications"
mkdir -p "$TARGET"
pkill -x Screenshooter 2>/dev/null || true
rm -rf "$TARGET/Screenshooter.app"
cp -R dist/Screenshooter.app "$TARGET/"

# Files from versions before 1.2, when the app lived in ~/bin.
rm -f "$HOME/bin/screenshot-sorter" "$HOME/bin/screenshot-compress.sh"

open "$TARGET/Screenshooter.app"
echo "Installed to $TARGET/Screenshooter.app."
echo "Connect Claude: claude mcp add --scope user screenshooter \"$TARGET/Screenshooter.app/Contents/MacOS/screenshooter-mcp\""
