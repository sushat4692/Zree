# Zree

**Zero-friction Markdown tree.**（*Zero* + *Tree*）

軽量な Markdown ノートアプリ。**macOS + Android**、UIは完全ネイティブ、ロジックは Rust の共有コア。

- **Zero friction** — 一瞬で起動する。肥大したUIなし、手動のフォルダ管理なし
- **Markdown at its core** — 純粋でポータブルなプレーンテキスト
- **Git-synced Tree** — Gitのツリー構造に乗せる。バージョン管理とデバイス間同期
- **Self-organizing** — 書くことに集中。自動タグ付けが思考を木構造へ編む（将来）

繋がり方は **タグが主、標準Markdownリンクが従**。`[[wikilink]]` は使わない。

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
| ⇧⌘U | 同期（commit → pull → push） |
| ⌘, | 設定（リモートURL / トークン） |
| ⇧⌘R | 再インデックス（git pull 後など） |
| ⇧⌘F | Finderで表示 |

## Git同期

- リポジトリはVaultそのもの（`.git` を同居させる）
- 同期 = commit（全変更）→ pull（ff かマージ）→ push。衝突時は push せず停止
- 衝突は `自分 / 相手 / 両方` を選んで解決 → 「マージ確定」でコミット＆push
- 認証: HTTPS + PAT、または ssh-agent
- リモートURLとトークンは ⌘, の設定から

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
- [x] ノート間リンク（標準Markdown `[表示名](ノート.md)` をクリックで遷移）
- [x] Git同期（libgit2: commit/pull/push、fast-forward、マージ）＋衝突UI
- [ ] Android

## テスト

```bash
cargo test -p zree-core
cargo run --release --example probe -- /path/to/vault
```
