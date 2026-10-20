#!/bin/bash
# Removes Screenshooter and sends screenshots back to the Desktop. Leaves ~/Screenshots alone.
set -uo pipefail

LABEL=com.screenshooter.sorter

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
pkill -x Screenshooter 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/bin/screenshot-sorter" "$HOME/bin/screenshot-compress.sh"
rm -rf /Applications/Screenshooter.app "$HOME/Applications/Screenshooter.app"
defaults delete com.apple.screencapture location 2>/dev/null
killall SystemUIServer 2>/dev/null
command -v claude >/dev/null && claude mcp remove --scope user screenshooter >/dev/null 2>&1

echo "Removed. Sorted files are still in ~/Screenshots."
