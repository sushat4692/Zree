# Changelog — Zree for macOS

Versions are independent from Android; both apps embed the same Rust core.

## 0.2.0 (2026-11-25)

### Features

- Tags are written `@tag`. `#` is only the heading marker, so tag completion no longer
  swallows the space that starts a heading. Legacy `#tag` is not read any more; the vault was
  migrated with `scripts/migrate-tag-syntax.py`.
- Tag suggestions in the editor: chips for the tags the rules are sure about (title words,
  customer names, notes about the same customer, co-occurrence) and the rest behind "ほか ▾".
  Measured on the author's vault: 96% of tier-1 suggestions were right.
- Applying a chip is an ordinary edit — ⌘Z takes it back.

### Fixes

- `@` completion never offered anything: NSTextView's completion range did not include the
  `@`, so the core never saw a tag.
- A pull brought new files but the note list kept using the cached index, so notes added on
  another device did not appear until the app was restarted.
