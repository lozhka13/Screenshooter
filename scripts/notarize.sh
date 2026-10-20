#!/bin/bash
# Signs with a Developer ID, notarizes and staples the disk image — for when an Apple Developer
# account is available. One-time setup:
#   xcrun notarytool store-credentials screenshooter --apple-id you@example.com --team-id TEAMID
# Then:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
PROFILE=${NOTARY_PROFILE:-screenshooter}
VERSION=$(cat VERSION)

scripts/build-app.sh --dmg
codesign --force --timestamp --sign "$SIGN_IDENTITY" "dist/Screenshooter-$VERSION.dmg"
xcrun notarytool submit "dist/Screenshooter-$VERSION.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "dist/Screenshooter-$VERSION.dmg"
spctl --assess --type open --context context:primary-signature -v "dist/Screenshooter-$VERSION.dmg"
echo "Notarized dist/Screenshooter-$VERSION.dmg"
