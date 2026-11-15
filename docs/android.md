# Zree Android — plan

Status: **not started**. The Android SDK is not installed on this machine, and the disk is at 91%
(41 GB free). This document splits the work into "doable without the SDK" and "needs the SDK",
and records the decisions that must be made before the first build.

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

## Phase 1 — the build spike (needs the SDK)

Installed via **command-line tools only** (no Android Studio download):

| Component | Approx. size |
|---|---|
| `cmdline-tools` | ~150 MB |
| `platforms;android-34` | ~60 MB |
| `build-tools;34.0.0` | ~120 MB |
| `ndk;27.x` | ~2.7 GB |
| Gradle/AGP downloads | ~300 MB |

Total ≈ 3.3 GB against 41 GB free. Feasible. Avoid emulator images (`~2 GB` each) — use a real
device over USB, since IME behaviour is the thing we must verify anyway.

Spike goals, in order:

1. `cargo build --target aarch64-linux-android` produces `libzree_core.so`
   (this is where libgit2/OpenSSL cross-compilation either works or does not)
2. a Compose activity loads the `.so` through the generated bindings and prints the vault count
3. verify Japanese input in `BasicTextField` (composition, cursor stability, long notes)

If step 1 fights back, stop and re-evaluate option 3 above before writing UI code.

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
