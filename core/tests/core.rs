use note_core::markdown::{self, Block, Inline};
use note_core::search::{self, Index};
use note_core::tags;
use note_core::vault::Vault;
use std::fs;

fn fixture() -> (tempfile::TempDir, Vault) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();

    fs::create_dir_all(root.join("assets")).unwrap();
    fs::write(root.join("assets/2025-05-16-101726.png"), b"\x89PNG").unwrap();
    fs::create_dir_all(root.join(".obsidian")).unwrap();
    fs::write(root.join(".obsidian/workspace.json"), "{}").unwrap();
    fs::create_dir_all(root.join("sub")).unwrap();

    fs::write(
        root.join("ワンネス メンタリング 230502.md"),
        "#ワンネス #メンタリング\n- 1ヶ月振り返り\n  - 8点 - コミュニケーション周りで減点\n- 課題\n  - コミュニケーション\n- 行動目標\n  - 月イチ面談\n![[Screenshot 2025-05-16 at 10.17.26 AM.png]]\n",
    )
    .unwrap();

    fs::write(
        root.join("1on1導入講座 240404.md"),
        "# 1on1導入講座\n\n導入の目的は **信頼関係** の構築。\n\n```md\n#これはコードブロックなのでタグではない\n```\n\n顧客は #CUBLIC様 と #採用 の文脈。\n![](assets/2024-06-23-124506.png)\n",
    )
    .unwrap();

    fs::write(root.join("sub/メモ.md"), "今日の記事を書いた。\n").unwrap();

    let vault = Vault::open(root).unwrap();
    (dir, vault)
}

#[test]
fn lists_markdown_only_and_skips_hidden_dirs() {
    let (_dir, vault) = fixture();
    let notes = vault.list().unwrap();
    let ids: Vec<&str> = notes.iter().map(|n| n.id.as_str()).collect();
    assert_eq!(notes.len(), 3, "got {ids:?}");
    assert!(ids.contains(&"sub/メモ.md"));
    assert!(!ids.iter().any(|i| i.contains("workspace.json")));
    assert!(!ids.iter().any(|i| i.starts_with("assets/")));
}

#[test]
fn read_and_write_roundtrip() {
    let (_dir, vault) = fixture();
    let body = vault.read("sub/メモ.md").unwrap();
    assert_eq!(body, "今日の記事を書いた。\n");

    let meta = vault.write("sub/メモ.md", "書き換えた\n").unwrap();
    assert_eq!(meta.title, "メモ");
    assert_eq!(vault.read("sub/メモ.md").unwrap(), "書き換えた\n");
}

#[test]
fn create_uses_untitled_stamp_and_avoids_collisions() {
    let (_dir, vault) = fixture();
    let a = vault.create(None, "メモ\n").unwrap();
    assert!(a.title.starts_with("Untitled "), "{}", a.title);

    let b = vault.create(Some("打ち合わせ"), "本文\n").unwrap();
    assert_eq!(b.id, "打ち合わせ.md");

    let c = vault.create(Some("打ち合わせ"), "2つ目\n").unwrap();
    assert_eq!(c.id, "打ち合わせ 2.md");
}

#[test]
fn title_sanitizing_blocks_path_traversal() {
    let (_dir, vault) = fixture();
    let m = vault.create(Some("../../etc/passwd"), "x").unwrap();
    assert!(m.id.ends_with("passwd.md"));
    assert!(!m.id.contains(".."));
    assert!(vault.path_of("../../etc/passwd").is_err());
    assert!(vault.create(Some("   "), "x").is_err());
}

#[test]
fn rename_keeps_body_and_reports_duplicates() {
    let (_dir, vault) = fixture();
    let m = vault.rename("sub/メモ.md", "日記").unwrap();
    assert_eq!(m.id, "sub/日記.md");
    assert_eq!(vault.read("sub/日記.md").unwrap(), "今日の記事を書いた。\n");

    vault.write("sub/占い.md", "既存\n").unwrap();
    let err = vault.rename("sub/日記.md", "占い");
    assert!(err.is_err());
}

#[test]
fn trash_moves_instead_of_deleting() {
    let (_dir, vault) = fixture();
    let id = vault.trash("sub/メモ.md").unwrap();
    assert_eq!(id, ".trash/メモ.md");
    assert!(!vault.exists("sub/メモ.md"));
    assert!(id.starts_with(".trash/"));
}

#[test]
fn tags_skip_headings_code_and_inline_code() {
    assert_eq!(
        tags::extract("#ワンネス #メンタリング\n- 課題"),
        vec!["ワンネス", "メンタリング"]
    );
    assert_eq!(tags::extract("# 見出しです\n"), Vec::<String>::new());
    assert_eq!(tags::extract("```\n#コード\n```\n#本物"), vec!["本物"]);
    assert_eq!(tags::extract("これは `#コード` です #タグ"), vec!["タグ"]);
    assert_eq!(tags::extract("顧客は #CUBLIC様 と #採用 の文脈。"), vec![
        "CUBLIC様",
        "採用"
    ]);
    assert_eq!(tags::extract("#重複 #重複"), vec!["重複"]);
    assert_eq!(tags::extract("色は #fff のような番号は除外"), Vec::<String>::new());
}

#[test]
fn japanese_substring_search_without_tokenizing() {
    let (_dir, vault) = fixture();
    let index = Index::build(&vault).unwrap();

    let hits = index.search("メンタリング", &[], 10);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, "ワンネス メンタリング 230502.md");

    // split across words in the original text: "月イチ面談" is found by "面談"
    let hits = index.search("面談", &[], 10);
    assert_eq!(hits.len(), 1);

    // full-width / half-width and case are normalized
    let hits = index.search("ｃｕｂｌｉｃ", &[], 10);
    assert_eq!(hits.len(), 1, "NFKC + lowercase normalization");
}

#[test]
fn tag_filter_and_tag_cloud() {
    let (_dir, vault) = fixture();
    let index = Index::build(&vault).unwrap();

    let hits = index.search("", &["採用".to_string()], 10);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, "1on1導入講座 240404.md");

    let cloud = index.tags();
    assert!(cloud.iter().any(|t| t.tag == "ワンネス" && t.count == 1));
    assert!(cloud.iter().any(|t| t.tag == "採用" && t.count == 1));
    assert!(cloud.iter().all(|t| t.count >= 1));
}

#[test]
fn empty_query_lists_everything() {
    let (_dir, vault) = fixture();
    let index = Index::build(&vault).unwrap();
    assert_eq!(index.search("", &[], 0).len(), 3);
}

#[test]
fn markdown_blocks_and_both_image_syntaxes() {
    let (_dir, vault) = fixture();
    let a = vault.read("ワンネス メンタリング 230502.md").unwrap();
    let blocks = markdown::parse_blocks(&a);
    assert!(matches!(blocks[0], Block::Paragraph { .. }));
    assert!(blocks.iter().any(|b| matches!(
        b,
        Block::Image { src, .. } if src == "Screenshot 2025-05-16 at 10.17.26 AM.png"
    )));

    let b = vault.read("1on1導入講座 240404.md").unwrap();
    let blocks = markdown::parse_blocks(&b);
    assert!(matches!(blocks[0], Block::Heading { level: 1, .. }));
    assert!(blocks.iter().any(|x| matches!(x, Block::Code { lang, .. } if lang == "md")));
    assert!(blocks.iter().any(|x| matches!(
        x,
        Block::Image { src, .. } if src == "assets/2024-06-23-124506.png"
    )));

    let inline = markdown::parse_inline("目的は **信頼関係** の構築。");
    assert!(inline.iter().any(|i| matches!(i, Inline::Bold(t) if t == "信頼関係")));

    assert_eq!(markdown::image_sources(&b), vec!["assets/2024-06-23-124506.png"]);
}

#[test]
fn list_items_capture_indent_and_checkboxes() {
    let blocks = markdown::parse_blocks("- [ ] 未完了\n  - [x] 完了\n- 普通\n");
    assert!(matches!(blocks[0], Block::ListItem { checked: Some(false), indent: 0, .. }));
    assert!(matches!(blocks[1], Block::ListItem { checked: Some(true), indent: 1, .. }));
    assert!(matches!(blocks[2], Block::ListItem { checked: None, .. }));
}

#[test]
fn normalize_is_idempotent_for_mixed_width() {
    assert_eq!(search::normalize("ＡＢＣ　ｄｅｆ"), search::normalize("abc def"));
}
