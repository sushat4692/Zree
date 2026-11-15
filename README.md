<p align="center">
  <img src="docs/assets/zree-logo.png" width="380" alt="Zree — zero-friction Markdown tree">
</p>

# Zree

**Zero-friction Markdown tree.** (*Zero* + *Tree*)

A lightweight Markdown note-taking app: **macOS + Android**, fully native UI, one shared Rust core.

- **Zero friction** — launches instantly. No bloated UI, no manual folder management.
- **Markdown at its core** — pure, portable plain text that you own.
- **Git-synced Tree** — built on Git's tree structure, so notes are versioned and synced across devices.
- **Self-organizing** — focus on writing; automatic tagging weaves your thoughts into a connected tree (future).

Connections are made by **tags first, standard Markdown links second**. `[[wikilink]]` syntax is not used.

Identifier: `im.sush.zree`

## Layout

```
core/          Rust: vault IO / Japanese search / tags / markdown tokenizer / git (uniffi)
macos/         SwiftUI app (NSTextView = the OS text system, so IME just works)
android/       Kotlin + Compose (skeleton; SDK not installed yet)
docs/spec.md   the contract both platforms must follow
docs/android.md  Android plan and open decisions
```

The macOS app is built with SwiftPM and ad-hoc signing — no Xcode project.
The link needs OpenSSL (a side effect of git2's `https` feature); Homebrew's
`openssl@3`/`openssl@4` is used automatically, override with `ZREE_OPENSSL_LIB`.

## macOS

```bash
./macos/scripts/sync-core.sh   # build Rust → generate Swift bindings → XCFramework
./macos/scripts/bundle.sh      # produces build/Zree.app (compiles the icon with actool)
open build/Zree.app
```

The app icon is an Icon Composer bundle (`macos/Resources/Zree.icon`), compiled at bundle
time; the Android icon is generated from the same source. The UI palette is sampled from it
too: tree `#559955` -> accent `#3C7D57`, trunk `#22323F`, background `#FAFAF6`/`#DCEBE0`.

Android shows a splash screen (Android 12+ SplashScreen API) with the tree on the paper
background; macOS has no splash by convention.

### Shortcuts

| Key | Action |
|---|---|
| ⌘N | New note (`Untitled yyMMdd-HHmm`, rename later) |
| ⌘S | Save (also autosaves 600 ms after typing stops) |
| ⇧⌘P | Toggle preview pane |
| ⇧⌘O | Open a vault folder |
| ⇧⌘C | Clone a vault from Git |
| ⇧⌘U | Sync (commit → pull → push) |
| ⌘, | Settings (auto-sync interval, remote URL, PAT) |
| ⇧⌘R | Reindex (e.g. after pulling) |
| ⇧⌘F | Reveal in Finder |

## Git sync

- The vault **is** the repository (`.git` lives next to the notes).
- Sync = commit all changes → pull → push. Each step is skipped when it would be a no-op:
  no commit without changes, and **no push unless the branch is ahead of the remote**.
- Pull fast-forwards when possible; otherwise it merges. On conflicts it stops without pushing and hands the file list to the UI.
- Conflicts are resolved per file as `mine / theirs / both`, then finalised with a merge commit.
- Auth: HTTPS + PAT (stored in the macOS Keychain). ssh-agent is not compiled in yet.
- Pulling on launch only happens when the worktree is clean, nothing is merging and the branch is actually behind.
- **Auto-sync is on by default** (every 5 minutes: commit → pull → push). It only commits when files changed, pauses while conflicts are open, stops after 3 consecutive failures, and runs once more on quit. Configurable at ⌘, (1/5/10/15 min or off).

## Performance (real vault: 365 notes / 443 KB)

| Operation | Time |
|---|---|
| Vault scan | 60 ms |
| Index build | 41 ms |
| One search | 200–300 µs |

## Status

- [x] Core: vault IO / search / tags / markdown
- [x] uniffi bindings (Swift; Kotlin can be generated)
- [x] macOS: list, search, tag filtering, editor, autosave, preview
- [x] Standard Markdown links that navigate between notes
- [x] Git sync (commit/pull/push, fast-forward, merge) with a conflict UI
- [x] Clone onboarding, Keychain-backed PAT, pull on launch
- [~] Android: runs on a device — clone/setup, list, search, tags, editor with autosave, manual sync
- [ ] Image syntax migration (`![[..]]` → `![](assets/..)`, 6 files)

## Tests

```bash
cargo test -p zree-core
cargo run --release --example probe -- /path/to/vault
```
