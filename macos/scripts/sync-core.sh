#!/usr/bin/env bash
# Build the Rust core, regenerate Swift bindings, and package it as an XCFramework.
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "==> cargo build --release"
cargo build --release -p note-core

echo "==> uniffi bindings (swift)"
rm -rf /tmp/note-bind macos/include
mkdir -p /tmp/note-bind macos/include macos/Frameworks macos/Sources/NoteCore
cargo run -q --bin uniffi-bindgen -- generate \
  --library target/release/libnote_core.dylib \
  --language swift --out-dir /tmp/note-bind

cp /tmp/note-bind/note_coreFFI.h macos/include/
cp /tmp/note-bind/note_coreFFI.modulemap macos/include/module.modulemap
cp /tmp/note-bind/note_core.swift macos/Sources/NoteCore/note_core.swift

echo "==> xcframework"
rm -rf macos/Frameworks/note_coreFFI.xcframework
xcodebuild -create-xcframework \
  -library target/release/libnote_core.a \
  -headers macos/include \
  -output macos/Frameworks/note_coreFFI.xcframework >/dev/null

echo "ok: macos/Frameworks/note_coreFFI.xcframework"
