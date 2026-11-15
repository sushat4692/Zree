# AGENTS.md — Zree

## プロジェクト名

**Zree** — *Zero-friction Markdown tree*（*Zero* + *Tree*）

> A lightweight, Markdown-first note-taking app designed to stay out of your way.

ブランディングの4本柱。README / UIコピー / アイコンはこの語彙に合わせる:

- **Zero friction** — 一瞬で起動する。肥大したUIなし、手動のフォルダ管理なし
- **Markdown at its core** — 純粋でポータブルなプレーンテキスト
- **Git-synced Tree** — Gitのツリー構造に乗せる。バージョン管理とデバイス間同期
- **Self-organizing** — 書くことに集中。自動タグ付けが思考を木構造へ編む（将来）

識別子:

| 対象 | 値 |
|---|---|
| bundle id (macOS) | `im.sush.zree` |
| Android applicationId | `im.sush.zree`（予定） |
| crate | `zree-core`（lib `zree_core`） |
| Swift パッケージ | `Zree` / target `ZreeCore` / 実行ファイル `Zree` |
| FFI | `zree_coreFFI`（uniffi 生成） |

## 前提（既存Vaultの実測値）

設計はこの実データに合わせてある:

- 365ノート / 443KB / 平均33行 / 10行未満が103件
- フォルダ0、frontmatter 0、dataview・mermaid・callout・表・数式 0、ノート間リンク 0
- 実使用: 見出し・箇条書き・打消し・チェックボックス・インラインタグ・画像・Git同期
- タグは99種（`#お客様打合せ` x35, `#ワンネス` x16, `#マネジメント` x15, `#1on1` x13）

## 確定した設計判断

| 論点 | 決定 |
|---|---|
| 対象OS | macOS + Android（iOSは対象外） |
| UI | 完全ネイティブ（WebView/JSなし）。SwiftUI + Compose |
| ロジック | Rust共有コア（uniffi） |
| エディタ | NSTextView / BasicTextField（OS標準IMEをそのまま使う） |
| 保存形式 | フラットな `.md`。フォルダ運用なし、命名規約なし（人間の運用でカバー） |
| 検索 | NFKC正規化＋小文字化＋部分一致（空白で区切らない日本語のため） |
| タグ | インラインタグ。絞り込みUI。自動タグ付けは将来 |
| クイックキャプチャ | **不採用**（「アプリを立ち上げて書く」癖があるため） |
| テンプレート | 保留（将来） |
| 画像 | 標準Markdown `![](path)` に移行する方針。`assets/YYYY-MM-DD-HHMMSS.ext`。移行は**アプリ完成後** |
| 配布 | macOS: ad-hoc署名の`.app` / Android: APK直入れ |

## やらないこと

frontmatterエディタ、リンクグラフ/バックリンク、プラグイン機構、表・数式・Mermaid・callout、Git LFS、フォルダツリーUI、グローバルホットキー、共有シート。

## 構成

```
core/    Rust: Vault IO / 検索 / タグ / Markdownトークナイザ / (Git=未実装)
macos/   SwiftUI（SwiftPM、Xcodeプロジェクトなし）
android/ 未着手
docs/    仕様
```

## コマンド

```bash
cargo test -p zree-core
cargo run --release --example probe -- /path/to/vault
./macos/scripts/sync-core.sh   # Rust → Swiftバインディング → XCFramework
./macos/scripts/bundle.sh      # build/Zree.app
```

## 現在の状態

- [x] コア（Vault/検索/タグ/Markdown）とテスト13件
- [x] uniffi バインディング（Swift、Kotlinは生成可）
- [x] macOS v0.1（検索・タグ絞り込み・編集・自動保存・プレビュー）
- [ ] Git同期（libgit2）+ 衝突UI
- [ ] Android
- [ ] 画像記法の移行（`![[..]]` → `![](assets/..)`、6件）
