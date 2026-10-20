#!/bin/bash
# Удаляет Screenshooter и возвращает скриншоты на Рабочий стол. Папку ~/Screenshots не трогает.
set -uo pipefail

LABEL=com.screenshooter.sorter

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/bin/screenshot-sorter" "$HOME/bin/screenshot-compress.sh"
defaults delete com.apple.screencapture location 2>/dev/null
killall SystemUIServer 2>/dev/null

echo "Удалено. Разобранные файлы остались в ~/Screenshots."
