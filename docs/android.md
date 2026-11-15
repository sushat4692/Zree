# Zree Android — plan

Status: **build spike passed**. The toolchain is installed and the core cross-compiles; nothing has
run on a device yet.

Installed (command-line tools only, no Android Studio download):

| Component | Version | Size |
|---|---|---|
| cmdline-tools | latest | 137 MB |
| platform-tools | 37.0.1 | — |
| platforms;android-34, android-35 | 3 | — |
| build-tools | 34.0.0, 35.0.0 | — |
| NDK | 27.2.12479018 | 2.7 GB |
| Gradle | 8.11.1 (wrapper committed) | 131 MB |

`~/Library/Android/sdk` totals ~2.9 GB.

### Spike results

- `./android/scripts/build-core.sh` produced `libzree_core.so` (9.0 MB) for `aarch64-linux-android`
  in 2m31s, including libgit2 and a vendored OpenSSL for HTTPS
- `./gradlew :app:assembleDebug` builds an 18 MB APK containing `libzree_core.so` and JNA
- the uniffi Kotlin bindings compile against JNA without changes
- **verified on a real device** (Android 16, arm64): uniffi + JNA load, Japanese substring
  search, Japanese tag extraction, markdown tokenising, and git status/commit through libgit2
  (`log: [smoke: commit from device]`)
- **not yet verified**: Japanese IME in `BasicTextField` (comes with the real editor)

Android 16 rail-guns (both fixed):
- shared libraries must be 16 KB page aligned → `RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"`
  plus JNA 5.17 and Compose BOM 2025.09 (which also raised compileSdk/targetSdk to 35)

## Things to decide first

### 1. Where does the vault live?

Android hands out `content://` URIs (SAF), not paths. The Rust core needs real paths.
Two options:

| Option | Consequences |
|---|---|
| **A. App-private storage** (`filesDir/vault`) — recommended | The core and libgit2 work with ordinary paths, identical to macOS. Import/export goes through SAF. The vault is not visible in other apps' file pickers. |
| B. Real external folder via SAF | Needs a Java-side file abstraction layer and every core call would have to be mediated — large refactor, and libgit2 cannot open a `content://` URI at all. |

Decision: **A**. Git is the source of truth, so the notes are never trapped; SAF is only used for
"import an existing folder" and "export a copy".

### 2. How does sync auth work?

macOS uses libgit2 + a PAT in the Keychain. On Android the equivalent is
`EncryptedSharedPreferences` (or the Keystore). Same PAT model, same HTTPS path.

### 3. Is shipping libgit2 to Android worth it?

This is the main technical risk. libgit2 on Android means:

- cross-compiling libgit2 + OpenSSL for `aarch64-linux-android` (and `x86_64` if we ever use an emulator)
- an NDK install (~2.7 GB) that cannot be removed if we want to rebuild

Fallback if that proves unreasonable: implement the Android Git layer with **JGit**
(pure Java, no NDK) and keep the Rust core for vault/search/tags/markdown only.
Cost: two Git implementations to keep in sync, which is exactly what the shared core was
supposed to avoid. Only take this path if the NDK build fails.

## Phase 0 — no SDK required (can start now)

- [x] Generate the Kotlin bindings with uniffi → `android/core-bindings/uniffi/zree_core/zree_core.kt`
      (128 KB; `ZreeSession`, `GitRepo`, `Block`, `Inline`, `Hit`, `NoteMeta`, `GitStatus`,
      `PullOutcome`, `ConflictChoice`, `NoteException`)
- [x] Gradle project skeleton (files only, not built yet)
- [x] This plan + the cross-platform contract in `docs/spec.md`
- [ ] Re-check the core for assumptions that break on Android: none known — `Vault::open` takes an
      absolute path and the core never touches macOS-only APIs

## Phase 1 — the build spike

- [x] `cargo build --target aarch64-linux-android` produces `libzree_core.so`
      (libgit2 + vendored OpenSSL cross-compile cleanly)
- [x] Gradle assembles an APK that packages the `.so` and JNA
- [x] a Compose activity loads the `.so` through the bindings and shows a note count
- [ ] verify Japanese input in `BasicTextField` (composition, cursor stability, long notes)

Avoid emulator images (~2 GB each) — use a real device over USB, since IME behaviour is the thing
we must verify anyway.

## Phase 2 — feature parity with macOS

- note list + incremental Japanese search (core already handles normalization)
- tag strip + filter
- editor (`BasicTextField` with `TextFieldState`) and a preview pane rendered from the `Block` stream
- link navigation (`zree://note?id=` equivalent: just call into the session)
- autosave with the same mtime overwrite guard

## Phase 3 — Git

- clone on first run (into `filesDir/vault`)
- sync = commit → pull → push, identical semantics to macOS (`docs/spec.md §6`)
- conflict screen with `mine / theirs / both` per file
- PAT in `EncryptedSharedPreferences`
- no pull-on-launch unless clean, as on macOS

## Phase 4 — Android-specific surface

- SAF import (copy an existing folder in) and export (write a zip/copy out)
- back handling (editor → list), and no quick capture by design

## Non-goals

Share sheet target, widgets, background sync service, Play Store distribution (APK sideload only).
