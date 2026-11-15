use zree_core::markdown::{self, Block, Inline};
use zree_core::search::{self, Index};
use zree_core::tags;
use zree_core::vault::Vault;
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
    fs::write(root.join("リンク元.md"), "#リンク\n[相手](sub/メモ.md)\n").unwrap();

    let vault = Vault::open(root).unwrap();
    (dir, vault)
}

#[test]
fn lists_markdown_only_and_skips_hidden_dirs() {
    let (_dir, vault) = fixture();
    let notes = vault.list().unwrap();
    let ids: Vec<&str> = notes.iter().map(|n| n.id.as_str()).collect();
    assert_eq!(notes.len(), 4, "got {ids:?}");
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
    assert_eq!(index.search("", &[], 0).len(), 4);
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

#[test]
fn resolves_markdown_links_in_every_notation() {
    let (_dir, vault) = fixture();
    let wide = "ワンネス メンタリング 230502.md";

    // percent-encoded (spaces)
    assert_eq!(
        vault.resolve_link("1on1導入講座 240404.md", "ワンネス%20メンタリング%20230502.md").as_deref(),
        Some(wide)
    );
    // raw, unencoded
    assert_eq!(
        vault.resolve_link("sub/メモ.md", "../ワンネス メンタリング 230502.md").as_deref(),
        Some(wide)
    );
    // same directory, no extension
    assert_eq!(vault.resolve_link("sub/メモ.md", "メモ").as_deref(), Some("sub/メモ.md"));
    // anchor / query are ignored
    assert_eq!(vault.resolve_link("sub/メモ.md", "メモ.md#課題").as_deref(), Some("sub/メモ.md"));
    // vault-absolute
    assert_eq!(vault.resolve_link("sub/メモ.md", "/sub/メモ.md").as_deref(), Some("sub/メモ.md"));
    // fully percent-encoded japanese
    assert_eq!(
        vault.resolve_link("sub/メモ.md", "%E3%83%A1%E3%83%A2.md").as_deref(),
        Some("sub/メモ.md")
    );
    // external links and misses
    assert_eq!(vault.resolve_link("sub/メモ.md", "https://example.com/x.md"), None);
    assert_eq!(vault.resolve_link("sub/メモ.md", "存在しない.md"), None);
    assert_eq!(vault.resolve_link("sub/メモ.md", "#見出しだけ"), None);
}

#[test]
fn inline_markers_consume_the_whole_delimiter() {
    assert_eq!(markdown::parse_inline("**a**"), vec![Inline::Bold("a".into())]);
    assert_eq!(markdown::parse_inline("~~a~~"), vec![Inline::Strike("a".into())]);
    assert_eq!(markdown::parse_inline("`a`"), vec![Inline::Code("a".into())]);
    assert_eq!(markdown::parse_inline("*a*"), vec![Inline::Italic("a".into())]);

    let source = "- **太字**と~~打消し~~と `code`";
    let spans = markdown::parse_inline(source);
    assert!(spans.iter().any(|s| matches!(s, Inline::Bold(t) if t == "太字")));
    assert!(spans.iter().any(|s| matches!(s, Inline::Strike(t) if t == "打消し")));
    assert!(spans.iter().any(|s| matches!(s, Inline::Code(t) if t == "code")));

    let leftover: String = spans
        .iter()
        .filter_map(|s| match s {
            Inline::Text(t) => Some(t.as_str()),
            _ => None,
        })
        .collect();
    assert!(
        !leftover.contains('*') && !leftover.contains('~') && !leftover.contains('`'),
        "stray markers survived: {leftover:?}"
    );
}

#[test]
fn list_continuation_rules() {
    use zree_core::complete::{list_action, ListAction};

    // continuation keeps the marker and the indentation
    assert_eq!(list_action("- 買い物"), ListAction::Continue { marker: "- ".into() });
    assert_eq!(list_action("* あ"), ListAction::Continue { marker: "* ".into() });
    assert_eq!(list_action("+ あ"), ListAction::Continue { marker: "+ ".into() });
    assert_eq!(list_action("  - 入れ子"), ListAction::Continue { marker: "  - ".into() });
    assert_eq!(list_action("    - 深い"), ListAction::Continue { marker: "    - ".into() });
    assert_eq!(list_action("\t- タブ"), ListAction::Continue { marker: "\t- ".into() });
    assert_eq!(list_action("  1. 手順"), ListAction::Continue { marker: "  2. ".into() });
    assert_eq!(list_action("3. 手順"), ListAction::Continue { marker: "4. ".into() });
    assert_eq!(list_action("10. 手順"), ListAction::Continue { marker: "11. ".into() });
    assert_eq!(list_action("> 引用"), ListAction::Continue { marker: "> ".into() });
    assert_eq!(list_action("  > 入れ子引用"), ListAction::Continue { marker: "  > ".into() });
    assert_eq!(
        list_action("- [x] 済み"),
        ListAction::Continue { marker: "- [ ] ".into() }
    );
    assert_eq!(
        list_action("- [ ] 未了"),
        ListAction::Continue { marker: "- [ ] ".into() }
    );

    // empty items: outdent one level, then leave the list
    assert_eq!(list_action("- "), ListAction::Replace { marker: "".into() });
    assert_eq!(list_action("  - "), ListAction::Replace { marker: "- ".into() });
    assert_eq!(list_action("    - "), ListAction::Replace { marker: "  - ".into() });
    assert_eq!(list_action("\t- "), ListAction::Replace { marker: "- ".into() });
    assert_eq!(list_action("  1. "), ListAction::Replace { marker: "1. ".into() });
    assert_eq!(list_action("  > "), ListAction::Replace { marker: "> ".into() });
    assert_eq!(list_action("- [ ] "), ListAction::Replace { marker: "".into() });

    // not a list
    assert_eq!(list_action("普通の段落"), ListAction::None);
    assert_eq!(list_action("#見出しではない"), ListAction::None);
}

#[test]
fn completion_context_detection() {
    use zree_core::complete::{completion_context, CompletionKind};

    let ctx = completion_context("本文 #お客").unwrap();
    assert_eq!(ctx.kind, CompletionKind::Tag);
    assert_eq!(ctx.prefix, "お客");

    // inside a sentence, not at a word boundary
    assert!(completion_context("a#b").is_none());
    // a heading is not a tag (the space after # is what separates them)
    assert!(completion_context("# 見出し").is_none());
    // fenced code is ignored
    assert!(completion_context("```\n#お客").is_none());
    assert!(completion_context("```\ncode\n```\n#お客").is_some());

    let link = completion_context("参考 [お客様").unwrap();
    assert_eq!(link.kind, CompletionKind::Note);
    assert_eq!(link.prefix, "お客様");

    let target = completion_context("参考 [x](お客").unwrap();
    assert_eq!(target.kind, CompletionKind::NoteTarget);
    assert_eq!(target.prefix, "お客");
}

#[test]
fn suggestions_filter_by_prefix_and_ignore_width() {
    let (_dir, vault) = fixture();
    let index = Index::build(&vault).unwrap();

    let tags = index.suggest_tags("ワン", 10);
    assert_eq!(tags, vec!["ワンネス"]);

    // full-width / half-width and case collapse
    assert_eq!(index.suggest_tags("ｃｕｂ", 10), vec!["CUBLIC様"]);

    let notes = index.suggest_notes("リンク", 10);
    assert!(notes.iter().any(|n| n.title == "リンク元"));
}

#[test]
fn full_width_hash_from_japanese_ime_is_accepted() {
    use zree_core::complete::{completion_context, CompletionKind};

    // Japanese IMEs turn "\#" into "＃"; both must behave the same
    assert_eq!(tags::extract("- ＃お客様"), vec!["お客様"]);
    let ctx = completion_context("- ＃お客").unwrap();
    assert_eq!(ctx.kind, CompletionKind::Tag);
    assert_eq!(ctx.prefix, "お客");
    // full-width space also separates a tag
    let ctx = completion_context("本文　＃お客").unwrap();
    assert_eq!(ctx.prefix, "お客");
}

#[test]
fn tag_completion_accepts_list_markers_as_boundary() {
    use zree_core::complete::{completion_context, CompletionKind};

    // an IME can eat the space after "- ", so "-#tag" must still complete
    let ctx = completion_context("-\u{ff03}").unwrap();
    assert_eq!(ctx.kind, CompletionKind::Tag);
    assert_eq!(ctx.prefix, "");
    assert_eq!(completion_context("- #お客").unwrap().prefix, "お客");
    // but a word glued to the hash is not a tag
    assert!(completion_context("ab#cd").is_none());
}

#[test]
fn tabs_indent_lists_in_the_preview() {
    let blocks = markdown::parse_blocks("- 親\n\t- 子\n\t\t- 孫\n");
    let indents: Vec<u8> = blocks
        .iter()
        .filter_map(|b| match b {
            Block::ListItem { indent, .. } => Some(*indent),
            _ => None,
        })
        .collect();
    assert_eq!(indents, vec![0, 1, 2]);
}

#[test]
fn indent_commands_move_list_lines_one_level() {
    use zree_core::complete::indent_list_line;

    assert_eq!(indent_list_line("- あ", false).unwrap(), "  - あ");
    assert_eq!(indent_list_line("    - あ", true).unwrap(), "  - あ");
    assert_eq!(indent_list_line("  - あ", true).unwrap(), "- あ");
    assert_eq!(indent_list_line("- あ", true).unwrap(), "- あ"); // already at the margin
    assert_eq!(indent_list_line("\t- あ", false).unwrap(), "\t  - あ");
    assert_eq!(indent_list_line("\t- あ", true).unwrap(), "- あ");
    assert_eq!(indent_list_line("1. あ", false).unwrap(), "  1. あ");
    assert_eq!(indent_list_line("> あ", false).unwrap(), "  > あ");
    assert_eq!(indent_list_line("- [ ] あ", false).unwrap(), "  - [ ] あ");
    // not a list: the UI should do nothing
    assert!(indent_list_line("ただの段落", false).is_none());
    assert!(indent_list_line("# 見出し", false).is_none());
}

#[test]
fn block_buttons_replace_and_toggle() {
    use zree_core::complete::{format_block, toggle_task, BlockKind};

    // replace the existing block instead of stacking markers
    assert_eq!(format_block("- foo", BlockKind::Task), "- [ ] foo");
    assert_eq!(format_block("- foo", BlockKind::Heading), "# foo");
    assert_eq!(format_block("# foo", BlockKind::Bullet), "- foo");
    assert_eq!(format_block("1. foo", BlockKind::Quote), "> foo");
    assert_eq!(format_block("> foo", BlockKind::Ordered), "1. foo");
    assert_eq!(format_block("foo", BlockKind::Bullet), "- foo");
    assert_eq!(format_block("foo", BlockKind::Ordered), "1. foo");
    assert_eq!(format_block("foo", BlockKind::Task), "- [ ] foo");

    // pressing the same block removes it
    assert_eq!(format_block("- foo", BlockKind::Bullet), "foo");
    assert_eq!(format_block("* foo", BlockKind::Bullet), "foo");
    assert_eq!(format_block("# foo", BlockKind::Heading), "foo");
    assert_eq!(format_block("> foo", BlockKind::Quote), "foo");
    assert_eq!(format_block("1. foo", BlockKind::Ordered), "foo");
    assert_eq!(format_block("- [ ] foo", BlockKind::Task), "foo");

    // indentation survives
    assert_eq!(format_block("  - foo", BlockKind::Heading), "  # foo");
    assert_eq!(format_block("  - foo", BlockKind::Bullet), "  foo");

    // checkbox toggle
    assert_eq!(toggle_task("- [ ] foo"), "- [x] foo");
    assert_eq!(toggle_task("- [x] foo"), "- [ ] foo");
    assert_eq!(toggle_task("- foo"), "- [ ] foo");
    assert_eq!(toggle_task("# foo"), "- [ ] foo");
    assert_eq!(toggle_task("foo"), "- [ ] foo");
    assert_eq!(toggle_task("  - [x] foo"), "  - [ ] foo");
}

#[test]
fn inline_marker_toggles_instead_of_stacking() {
    use zree_core::complete::toggle_inline;

    // no selection: insert a pair and put the caret between them
    let r = toggle_inline("foo", 3, 3, "**");
    assert_eq!(r.text, "foo****");
    assert_eq!((r.sel_start, r.sel_end), (5, 5));

    // pressing again inside the empty pair removes it
    let r2 = toggle_inline(&r.text, r.sel_start, r.sel_end, "**");
    assert_eq!(r2.text, "foo");

    // selection gets wrapped, then unwrapped
    let r = toggle_inline("foo", 0, 3, "**");
    assert_eq!(r.text, "**foo**");
    let r2 = toggle_inline(&r.text, r.sel_start, r.sel_end, "**");
    assert_eq!(r2.text, "foo");

    // selection that already contains the markers
    let r = toggle_inline("**foo**", 0, 7, "**");
    assert_eq!(r.text, "foo");

    // caret inside a bold span removes the pair
    let r = toggle_inline("a **foo** b", 5, 5, "**");
    assert_eq!(r.text, "a foo b");
    assert_eq!((r.sel_start, r.sel_end), (3, 3));

    // caret in plain text far from any marker still wraps
    let r = toggle_inline("foo bar", 2, 2, "**");
    assert_eq!(r.text, "fo****o bar");

    // emoji (surrogate pairs) are handled as characters, not bytes
    let r = toggle_inline("😀", 1, 1, "**");
    assert_eq!(r.text, "😀****");
}

#[test]
fn notes_can_be_sorted_four_ways() {
    use zree_core::search::SortOrder;

    let (_dir, vault) = fixture();
    let index = Index::build(&vault).unwrap();

    let titles = |order| -> Vec<String> {
        index.list_rows(order).into_iter().map(|n| n.title).collect()
    };

    let mut title_asc = titles(SortOrder::TitleAsc);
    let mut expected = title_asc.clone();
    expected.sort();
    assert_eq!(title_asc, expected);

    // every row carries a snippet for the list
    assert!(index.list_rows(SortOrder::UpdatedDesc).iter().any(|r| !r.snippet.is_empty()));

    title_asc.reverse();
    assert_eq!(titles(SortOrder::TitleDesc), title_asc);

    // updated orders are monotonic in mtime
    let desc = index.list_rows(SortOrder::UpdatedDesc);
    assert!(desc.windows(2).all(|w| w[0].mtime_ms >= w[1].mtime_ms));
    let asc = index.list_rows(SortOrder::UpdatedAsc);
    assert!(asc.windows(2).all(|w| w[0].mtime_ms <= w[1].mtime_ms));
}

#[test]
fn thematic_breaks_are_rules_not_paragraphs() {
    for source in ["---", "***", "___", " - - - ", "----"] {
        let blocks = markdown::parse_blocks(source);
        assert!(
            matches!(blocks.as_slice(), [Block::Rule { .. }]),
            "{source:?} should be a rule, got {blocks:?}"
        );
    }
    // not rules
    assert!(matches!(
        markdown::parse_blocks("- item").as_slice(),
        [Block::ListItem { .. }]
    ));
    assert!(matches!(
        markdown::parse_blocks("--").as_slice(),
        [Block::Paragraph { .. }]
    ));
    assert!(matches!(
        markdown::parse_blocks("**bold**").as_slice(),
        [Block::Paragraph { .. }]
    ));
}
