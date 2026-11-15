#!/usr/bin/env bash
# Build the Rust core, regenerate Swift bindings, and package it as an XCFramework.
set -euo pipefail
cd "$(dirname "$0")/../.."

# keep the Rust objects at the same deployment target as the app
export MACOSX_DEPLOYMENT_TARGET=14.0

CRATE=zree_core
PKG=zree-core
BIND=/tmp/zree-bind

echo "==> cargo build --release ($PKG)"
cargo build --release -p "$PKG"

echo "==> uniffi bindings (swift)"
rm -rf "$BIND" macos/include
mkdir -p "$BIND" macos/include macos/Frameworks macos/Sources/ZreeCore
cargo run -q --bin uniffi-bindgen -- generate \
  --library "target/release/lib${CRATE}.dylib" \
  --language swift --out-dir "$BIND"

cp "$BIND/${CRATE}FFI.h" macos/include/
cp "$BIND/${CRATE}FFI.modulemap" macos/include/module.modulemap
cp "$BIND/${CRATE}.swift" macos/Sources/ZreeCore/

echo "==> xcframework"
rm -rf "macos/Frameworks/${CRATE}FFI.xcframework"
xcodebuild -create-xcframework \
  -library "target/release/lib${CRATE}.a" \
  -headers macos/include \
  -output "macos/Frameworks/${CRATE}FFI.xcframework" >/dev/null

echo "ok: macos/Frameworks/${CRATE}FFI.xcframework"
