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

### TLS trust store (the second big landmine)

`openssl-src` **forces `no-stdio` for Android**, so the vendored OpenSSL cannot open
any file. libgit2 loads CA certificates from a file, which therefore fails with
`x509 certificate routines::BIO lib`. `SSL_CERT_FILE`, `set_ssl_cert_file` and a
certificate directory all fail for the same reason.

Workaround (in `core/src/ffi.rs`, Android only):

1. the app concatenates the system roots into `filesDir/ca-bundle.pem`
   (`CaBundle.kt`; ~120 certificates)
2. the core calls `git_libgit2_init()` first — libgit2 creates its `SSL_CTX` there,
   and skipping this segfaults
3. each PEM certificate is parsed in memory (`PEM_read_bio_X509`) and registered with
   libgit2's internal `git_openssl__add_x509_cert()`

That last symbol is **not public API**. If a libgit2 upgrade removes or hides it, the
link fails; the fallback is to build OpenSSL ourselves without `no-stdio` and point
`OPENSSL_DIR` at it.

Verified end to end on the device: clone a private GitHub repo with a PAT, edit a note,
and the 1-minute auto-sync pushed `zree: autosync …` to the remote.

Conflict path verified too: a divergent edit on the Mac produced `衝突 1 件` on the device,
resolving with `相手` rewrote the file, and `マージ確定` produced `zree: resolve conflicts`
and pushed it as a merge commit.

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

Verified on the device:

- [x] setup screen: clone from Git (URL + PAT) or create an empty vault
- [x] note list with Japanese titles, snippets and per-note tags
- [x] tag strip filter (top 40 tags, AND)
- [x] editor: title field, rename, plain `BasicTextField`
- [x] autosave 700 ms after typing stops, with the same mtime overwrite guard
- [x] manual sync button and pull-on-open (same rules as macOS)

Still missing:

- [ ] Japanese IME under heavy composition / long notes (a short romaji→kana round trip worked:
      typed `appended-line`, the IME produced `あっぺんでｄ−ぃね`, and autosave persisted it)
      — verified on the device with the real UI too
- [x] Markdown preview pane rendered from the `Block` stream (headings, lists, checkboxes,
      quotes, code, images, bold/italic/strike/inline code)
- [x] link navigation from the preview
- [x] rename on focus loss (no explicit button) — also changed on macOS for parity
- [x] back gesture returns from the editor to the list instead of closing the app
- [x] auto-sync timer (default 5 min, 1/5/10/15 or off) plus a flush when the app is backgrounded
- [x] conflict UI: banner on the list, per-file `mine / theirs / both`, bulk actions,
      then a merge commit and push
- [x] SAF import (copy .md + assets from a picked folder, never overwriting) and
      export (write the vault into a picked folder)

## Phase 3 — Git

- clone on first run (into `filesDir/vault`)
- sync = commit → pull → push, identical semantics to macOS (`docs/spec.md §6`)
- conflict screen with `mine / theirs / both` per file
- PAT in `EncryptedSharedPreferences`
- no pull-on-launch unless clean, as on macOS

## Switching trees

The settings dialog has **ツリーを切り替え…**, which returns to the chooser; the chooser lists the
last five trees (tap to open, 外す to forget) next to clone / create-empty.

## Editor toolbar

The editor's assist bar sits at the bottom of the screen, directly above the soft keyboard
(`imePadding()` on the editor column + a `surfaceVariant` row with
`navigationBarsPadding`). Buttons: outdent, indent, bullet, checkbox, heading, bold.

## Phase 4 — Android-specific surface

- [x] SAF import (copy an existing folder in) and export (write the vault out)
- [x] back handling (editor → list, conflicts → list)
- no quick capture by design

Verified on the device: importing two notes from `Download/ZreeImport` added both to the
vault, and exporting wrote all four vault notes back into that folder.

## Non-goals

Share sheet target, widgets, background sync service, Play Store distribution (APK sideload only).
