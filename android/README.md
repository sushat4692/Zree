# Zree for Android

Status: **skeleton only** — no SDK on the build machine yet, so nothing here has been compiled.
See `../docs/android.md` for the plan and the open decisions.

## Regenerating the bindings

```bash
cargo build --release -p zree-core
cargo run --bin uniffi-bindgen -- generate \
  --library target/release/libzree_core.dylib \
  --language kotlin --out-dir android/core-bindings
```

Output: `android/core-bindings/uniffi/zree_core/zree_core.kt` (generated, committed for review).

## Once the SDK is installed

```bash
export ANDROID_HOME=~/Library/Android/sdk
cargo build --release --target aarch64-linux-android -p zree-core
cp target/aarch64-linux-android/release/libzree_core.so \
   android/app/src/main/jniLibs/arm64-v8a/
cd android && ./gradlew :app:assembleDebug
```

`local.properties` (with `sdk.dir=`) must exist for Gradle; it is gitignored.

## Launcher icon

Adaptive icon (API 26+, and minSdk is 26):

- `res/drawable/ic_launcher_background.xml` — vector gradient matching the Icon Composer
  background (top `#FAFAF6` → bottom `#DCEBE0`)
- `res/mipmap-*dpi/ic_launcher_foreground.png` — the tree layer, regenerated from the
  macOS icon source with:

```bash
swift android/scripts/make-icons.swift
```

- `res/mipmap-*/ic_launcher.png` are the legacy bitmaps, kept only as a fallback

Splash screen (`res/values/themes.xml`, mint background) uses the wordmark:

```bash
swift android/scripts/make-splash-logo.swift   # pads docs/assets/zree-logo.png onto a square
```

The square canvas matters: Android's splash icon slot is square and stretches
non-square drawables.

## Native dependencies

The core links libgit2. Cross-compiling it for Android is the risky step; if it fails,
`docs/android.md` records the fallback (JGit on the Kotlin side).
