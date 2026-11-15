# Note

Obsidian の代替として作る、軽量な Markdown ノートアプリ。
**macOS + Android**、UIは完全ネイティブ、ロジックは Rust の共有コア。

## なぜ作るか

既存の Vault（365ノート / 453KB）を実測したところ、Obsidian の機能のごく一部しか使っていなかった:

- フォルダ 0、frontmatter 0、dataview/mermaid/callout/表/数式 0、ノート間リンク 0
- 使っているのは: 見出し、箇条書き、打消し、チェックボックス、インラインタグ、画像埋め込み、Git同期
- タグは **99種**（`#お客様打合せ` x35, `#ワンネス` x16, `#マネジメント` x15, `#1on1` x13 …）

## 構成

```
core/      Rust: Vault IO / 日本語検索 / タグ抽出 / Markdownトークナイザ (uniffi)
macos/     SwiftUI アプリ (NSTextView = OS標準IME)
android/   Kotlin + Compose（未着手）
docs/      仕様（2OSで共有する挙動）
```

macOS は Xcode プロジェクトを使わず、SwiftPM + ad-hoc 署名で `.app` を組み立てる。

## macOS

```bash
./macos/scripts/sync-core.sh   # Rustをビルド → Swiftバインディング生成 → XCFramework
./macos/scripts/bundle.sh      # build/Note.app を作る
open build/Note.app
```

ショートカット:

| キー | 動作 |
|---|---|
| ⌘N | 新規ノート（タイトルは `Untitled yyMMdd-HHmm`、あとでリネーム可） |
| ⌘S | 保存（600ms無操作でも自動保存） |
| ⇧⌘P | プレビュー切り替え |
| ⇧⌘O | Vaultを開く |
| ⇧⌘R | 再インデックス（git pull 後など） |
| ⇧⌘F | Finderで表示 |

## 性能（実データ365ノート）

| 項目 | 値 |
|---|---|
| Vault走査 | 60ms |
| インデックス構築 | 41ms |
| 検索1回 | 200〜300µs |

## ステータス

- [x] コア: Vault IO / 検索 / タグ / Markdown
- [x] uniffi バインディング（Swift、Kotlinは生成可能）
- [x] macOS: 一覧・検索・タグ絞り込み・編集・自動保存・プレビュー
- [ ] Git同期（libgit2）＋衝突UI
- [ ] Android

## テスト

```bash
cargo test -p note-core
cargo run --release --example probe -- /path/to/vault
```
