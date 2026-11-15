# Zree

**Zero-friction Markdown tree.**（*Zero* + *Tree*）

軽量な Markdown ノートアプリ。**macOS + Android**、UIは完全ネイティブ、ロジックは Rust の共有コア。

- **Zero friction** — 一瞬で起動する。肥大したUIなし、手動のフォルダ管理なし
- **Markdown at its core** — 純粋でポータブルなプレーンテキスト
- **Git-synced Tree** — Gitのツリー構造に乗せる。バージョン管理とデバイス間同期
- **Self-organizing** — 書くことに集中。自動タグ付けが思考を木構造へ編む（将来）

識別子: `im.sush.zree`

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
./macos/scripts/bundle.sh      # build/Zree.app を作る
open build/Zree.app
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

## 性能（実データ365ノート / 443KB）

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
cargo test -p zree-core
cargo run --release --example probe -- /path/to/vault
```
