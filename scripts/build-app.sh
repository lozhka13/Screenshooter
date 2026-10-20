#!/bin/bash
# Builds dist/Screenshooter.app; with --dmg also the release disk image and zip.
# Needs Xcode or the Command Line Tools. SIGN_IDENTITY="Developer ID Application: …" signs for notarization
# (see scripts/notarize.sh); without it the app is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
DIST=dist
APP="$DIST/Screenshooter.app"

echo "Building Screenshooter ${VERSION}…"
swift build -c release --product Screenshooter
swift build -c release --product screenshooter-mcp
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Screenshooter" "$APP/Contents/MacOS/Screenshooter"
cp "$BIN/screenshooter-mcp" "$APP/Contents/MacOS/screenshooter-mcp"
install -m 755 scripts/screenshot-compress.sh "$APP/Contents/Resources/screenshot-compress.sh"
cp categories.example.json "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# App icon from the 1024 px master (assets/icon.svg rendered to assets/icon-1024.png).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.lozhka13.screenshooter</string>
  <key>CFBundleName</key><string>Screenshooter</string>
  <key>CFBundleDisplayName</key><string>Screenshooter</string>
  <key>CFBundleExecutable</key><string>Screenshooter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSMicrophoneUsageDescription</key><string>Screenshooter records your voice together with the screen when you start a recording.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Screenshooter transcribes your screen recordings on this Mac.</string>
  <key>NSAppleEventsUsageDescription</key><string>Screenshooter reads the address and title of the browser tab you took a screenshot of, to suggest a folder and name the file.</string>
  <key>NSHumanReadableCopyright</key><string>github.com/lozhka13/Screenshooter</string>
</dict>
</plist>
PL

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Hardened runtime for notarization; entitlements cover the microphone and browser automation.
  codesign --force --options runtime --timestamp --entitlements scripts/Screenshooter.entitlements \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/screenshooter-mcp"
  codesign --force --options runtime --timestamp --entitlements scripts/Screenshooter.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  # Ad hoc: runs on Apple Silicon, but macOS asks for confirmation on first launch.
  codesign --force --deep --sign - "$APP"
fi
echo "Built $APP"

if [ "${1:-}" = "--dmg" ]; then
  STAGE="$(mktemp -d)/Screenshooter"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DIST/Screenshooter-$VERSION.dmg" "$DIST/Screenshooter-$VERSION.zip"
  hdiutil create -quiet -volname "Screenshooter $VERSION" -srcfolder "$STAGE" -format UDZO \
    "$DIST/Screenshooter-$VERSION.dmg"
  rm -rf "$(dirname "$STAGE")"
  (cd "$DIST" && ditto -c -k --keepParent Screenshooter.app "Screenshooter-$VERSION.zip")
  echo "Built $DIST/Screenshooter-$VERSION.dmg and .zip"
fi
