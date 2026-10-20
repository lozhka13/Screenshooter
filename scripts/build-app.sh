#!/bin/bash
# Builds dist/Screenshooter.app; with --dmg also the release disk image and zip.
# Needs Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
DIST=dist
APP="$DIST/Screenshooter.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building Screenshooter ${VERSION}…"
xcrun swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/Screenshooter"
xcrun swiftc -O MCP/main.swift Sources/Config.swift -o "$APP/Contents/MacOS/screenshooter-mcp"

install -m 755 scripts/screenshot-compress.sh "$APP/Contents/Resources/screenshot-compress.sh"
cp categories.example.json "$APP/Contents/Resources/"

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
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>github.com/lozhka13/Screenshooter</string>
</dict>
</plist>
PL

# Ad-hoc signature: not notarized, but required to run on Apple Silicon and keeps the bundle intact.
codesign --force --deep --sign - "$APP"
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
