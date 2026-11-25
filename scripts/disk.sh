#!/usr/bin/env bash
# Disk usage: where the build artefacts go, and how to reclaim them.
#
#   ./scripts/disk.sh            report
#   ./scripts/disk.sh clean      drop what can be rebuilt (keeps sources and caches)
#   ./scripts/disk.sh clean-all  also drop download caches (slow to rebuild)
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
report() {
  echo "== repository =="
  du -sh "$ROOT" 2>/dev/null || true
  for dir in target macos/.build macos/Frameworks android/app/build android/.gradle; do
    [ -e "$ROOT/$dir" ] && du -sh "$ROOT/$dir" 2>/dev/null || true
  done
  echo "== outside =="
  for dir in "$HOME/.cargo/registry" "$HOME/.gradle" "$HOME/Library/Android/sdk"; do
    [ -e "$dir" ] && du -sh "$dir" 2>/dev/null || true
  done
  echo "== volume =="
  df -h "$HOME" | tail -1
}

clean() {
  echo "==> cargo clean (Rust artefacts)"
  cargo clean 2>/dev/null || true

  echo "==> swift build artefacts"
  rm -rf macos/.build

  echo "==> generated xcframework (rebuilt by macos/scripts/sync-core.sh)"
  rm -rf macos/Frameworks

  echo "==> gradle build outputs"
  (cd android && ./gradlew --stop >/dev/null 2>&1 || true)
  rm -rf android/app/build android/.gradle

  echo "==> app bundle"
  rm -rf build

  report
}

clean_all() {
  clean
  echo "==> gradle caches (all modules)"
  rm -rf "$HOME/.gradle/caches"
  echo "==> cargo registry cache (sources are re-downloaded)"
  rm -rf "$HOME/.cargo/registry/cache"
}

case "${1:-report}" in
  report) report ;;
  clean) clean ;;
  clean-all) clean_all ;;
  *) echo "usage: $0 [report|clean|clean-all]" >&2; exit 2 ;;
esac
