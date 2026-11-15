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

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP" 2>&1 | tail -2

echo "built: $APP"
