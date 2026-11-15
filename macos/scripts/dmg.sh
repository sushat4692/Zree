#!/usr/bin/env bash
# Build a distributable disk image: build/Zree.dmg
#
# The app is ad-hoc signed, so on another Mac Gatekeeper will ask first (right-click →
# Open, or `xattr -dr com.apple.quarantine /Applications/Zree.app`).
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="build/Zree.app"
DMG="build/Zree.dmg"
STAGE="build/dmg-stage"

./macos/scripts/bundle.sh

echo "==> staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil"
hdiutil create \
  -volname "Zree" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGE"

SIZE=$(du -h "$DMG" | cut -f1)
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "built: $DMG ($SIZE)"
echo "sha256: $SHA"
