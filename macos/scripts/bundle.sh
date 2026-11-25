#!/usr/bin/env bash
# Build Zree.app into build/ (ad-hoc signed, runs locally).
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ ! -d macos/Frameworks/zree_coreFFI.xcframework ]; then
  ./macos/scripts/sync-core.sh
fi

echo "==> swift build"
swift build -c release --package-path macos

APP="$PWD/build/Zree.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macos/.build/release/Zree "$APP/Contents/MacOS/Zree"
cp macos/Resources/Info.plist "$APP/Contents/Info.plist"

# The version lives in macos/VERSION so the release tooling and the bundle cannot disagree.
VERSION="$(cat macos/VERSION)"
BUILD="$((10#$(echo "$VERSION" | cut -d. -f1) * 10000 + 10#$(echo "$VERSION" | cut -d. -f2) * 100 + 10#$(echo "$VERSION" | cut -d. -f3)))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

echo "==> icon (actool)"
if [ -d macos/Resources/Zree.icon ]; then
  ICON="$PWD/macos/Resources/Zree.icon"
  xcrun actool "$ICON" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon Zree --output-partial-info-plist /tmp/zree-icon-partial.plist >/dev/null
  cp "$APP/Contents/Resources/Zree.icns" "$APP/Contents/Resources/" 2>/dev/null || true
fi

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP" 2>&1 | tail -2

echo "built: $APP"
