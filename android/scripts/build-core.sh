#!/usr/bin/env bash
# Cross-compile the Rust core for Android and drop the .so where Gradle picks it up.
set -euo pipefail
cd "$(dirname "$0")/../.."

: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
API=26
ABI=arm64-v8a
TARGET=aarch64-linux-android

NDK="${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)}"
if [ -z "${NDK:-}" ] || [ ! -d "$NDK" ]; then
  echo "NDK not found. Install it with: sdkmanager --install 'ndk;27.2.12479018'" >&2
  exit 1
fi

HOST_TAG=darwin-x86_64
[ -d "$NDK/toolchains/llvm/prebuilt/darwin-arm64" ] && HOST_TAG=darwin-arm64
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
export PATH="$TOOLCHAIN:$PATH"

export CC_aarch64_linux_android="aarch64-linux-android${API}-clang"
export CXX_aarch64_linux_android="aarch64-linux-android${API}-clang++"
export AR_aarch64_linux_android="llvm-ar"
export RANLIB_aarch64_linux_android="llvm-ranlib"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="aarch64-linux-android${API}-clang"

# Android 16 requires 16 KB page alignment for arm64 shared libraries
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"

echo "==> ndk: $NDK"
echo "==> cargo build --release --target $TARGET"
cargo build --release --target "$TARGET" -p zree-core

OUT="android/app/src/main/jniLibs/$ABI"
mkdir -p "$OUT"
cp "target/$TARGET/release/libzree_core.so" "$OUT/"
echo "ok: $OUT/libzree_core.so"
ls -lh "$OUT/libzree_core.so"
