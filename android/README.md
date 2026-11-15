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

## Native dependencies

The core links libgit2. Cross-compiling it for Android is the risky step; if it fails,
`docs/android.md` records the fallback (JGit on the Kotlin side).
