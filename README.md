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
android/       Kotlin + Compose (not started)
docs/spec.md   the contract both platforms must follow
```

The macOS app is built with SwiftPM and ad-hoc signing — no Xcode project.

## macOS

```bash
./macos/scripts/sync-core.sh   # build Rust → generate Swift bindings → XCFramework
./macos/scripts/bundle.sh      # produces build/Zree.app
open build/Zree.app
```

### Shortcuts

| Key | Action |
|---|---|
| ⌘N | New note (`Untitled yyMMdd-HHmm`, rename later) |
| ⌘S | Save (also autosaves 600 ms after typing stops) |
| ⇧⌘P | Toggle preview pane |
| ⇧⌘O | Open a vault folder |
| ⇧⌘C | Clone a vault from Git |
| ⇧⌘U | Sync (commit → pull → push) |
| ⌘, | Settings (remote URL, PAT) |
| ⇧⌘R | Reindex (e.g. after pulling) |
| ⇧⌘F | Reveal in Finder |

## Git sync

- The vault **is** the repository (`.git` lives next to the notes).
- Sync = commit all changes → pull → push. Nothing to commit is not an error.
- Pull fast-forwards when possible; otherwise it merges. On conflicts it stops without pushing and hands the file list to the UI.
- Conflicts are resolved per file as `mine / theirs / both`, then finalised with a merge commit.
- Auth: HTTPS + PAT (stored in the macOS Keychain) or ssh-agent.
- Pulling on launch only happens when the worktree is clean, nothing is merging and the branch is actually behind.

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
- [ ] Android
- [ ] Image syntax migration (`![[..]]` → `![](assets/..)`, 6 files)

## Tests

```bash
cargo test -p zree-core
cargo run --release --example probe -- /path/to/vault
```
