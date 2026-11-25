# Changelog — Zree for Android

Versions are independent from macOS; both apps embed the same Rust core.

## 0.2.0 (2026-11-25)

### Features

- Tags are written `@tag`. `#` is only the heading marker, so headings and tag completion no
  longer compete.
- Tag suggestions in the editor, with the same rules as macOS, plus the reason each tag was
  proposed.
- The note list keeps its scroll position when a note is closed and the list is shown again.

### Fixes

- A pull brought new files but the list kept using the cached index, so notes added on another
  device did not appear.
- A tag written by the core stayed invisible in the editor until the note was reopened.
