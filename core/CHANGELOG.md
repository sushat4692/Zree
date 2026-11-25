# Changelog — zree-core

The Rust core is compiled into both apps. Its version is independent of theirs; every build
records the core it bundled, so a misbehaving build can be traced back to a core release.

## 0.2.0 (2026-11-25)

### Features

- Tags are `@tag`; `#` is never a tag. Legacy `#tag` is no longer read — the vault was
  migrated with `scripts/migrate-tag-syntax.py`, which skips headings, code, colours and words
  glued to `#`.
- Tag suggestions from structure alone (`suggest_tags_for` / `apply_tags` / `tag_insertion`):
  title matches, customer names, sibling notes and co-occurrence. Measured at 96% precision
  for the reliable tier.
- `reindex()` puts the timestamps from Git back after rebuilding, and reapplies them after a
  pull.

### Fixes

- A pull changed files on disk but the cached index was reused, so new notes stayed invisible
  until the app restarted.
- Writing a note compared content instead of mtime, so a touch-only change is no longer a
  conflict.
