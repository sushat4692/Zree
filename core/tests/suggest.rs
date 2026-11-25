//! Tag suggestions and tag insertion, exercised through the same FFI the apps call.

use std::fs;
use std::sync::Arc;
use zree_core::ffi::ZreeSession;

/// A small vault shaped like the author's: tags on the first line, customer names in titles,
/// two trailing spaces for a hard break.
fn vault() -> (tempfile::TempDir, Arc<ZreeSession>) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    fs::write(
        root.join("Formosa様 230721.md"),
        "@Formosa様 @お客様打合せ\n- 進捗確認\n",
    )
    .unwrap();
    fs::write(
        root.join("Formosa様 230526.md"),
        "@Formosa様 @お客様打合せ\n- 仕様相談\n",
    )
    .unwrap();
    fs::write(root.join("Figma 261015.md"), "@Figma\n- コンポーネント整理\n").unwrap();
    // untagged: same customer as the two notes above
    fs::write(root.join("Formosa様 新規案件.md"), "初回の打合せ。\n").unwrap();
    let session = ZreeSession::open(root.to_string_lossy().to_string()).unwrap();
    (dir, session)
}

fn tags_of(session: &ZreeSession, id: &str) -> Vec<String> {
    session
        .suggest_tags_for(id.to_string(), 5)
        .unwrap()
        .into_iter()
        .map(|s| s.tag)
        .collect()
}

#[test]
fn an_untagged_note_gets_its_customer_and_what_siblings_carry() {
    let (_dir, session) = vault();
    let suggestions = tags_of(&session, "Formosa様 新規案件.md");
    assert_eq!(suggestions.first().map(|s| s.as_str()), Some("Formosa様"));
    assert!(
        suggestions.contains(&"お客様打合せ".to_string()),
        "the sibling notes both carry it: {suggestions:?}"
    );
}

#[test]
fn a_tag_that_is_a_title_word_is_proposed_again() {
    let (_dir, session) = vault();
    fs::write(
        _dir.path().join("Figma 集約.md"),
        "# 集約\nコンポーネントをまとめた。\n",
    )
    .unwrap();
    session.reindex().unwrap();
    assert_eq!(tags_of(&session, "Figma 集約.md"), vec!["Figma".to_string()]);
}

#[test]
fn suggestions_are_deterministic_and_skip_tags_already_written() {
    let (_dir, session) = vault();
    let first = session.suggest_tags_for("Formosa様 新規案件.md".to_string(), 5).unwrap();
    let second = session.suggest_tags_for("Formosa様 新規案件.md".to_string(), 5).unwrap();
    assert_eq!(
        first.iter().map(|s| &s.tag).collect::<Vec<_>>(),
        second.iter().map(|s| &s.tag).collect::<Vec<_>>()
    );
    assert!(first.iter().any(|s| s.tier == 1));

    let already = session.suggest_tags_for("Formosa様 230721.md".to_string(), 5).unwrap();
    assert!(
        !already.iter().any(|s| s.tag == "Formosa様" || s.tag == "お客様打合せ"),
        "tags on the note must not be offered again: {already:?}"
    );
}

#[test]
fn applying_tags_edits_the_tag_line_and_updates_the_index() {
    let (dir, session) = vault();
    let id = "Formosa様 新規案件.md";

    let updated = session.apply_tags(id.to_string(), vec!["Formosa様".to_string()]).unwrap().body;
    assert_eq!(updated, "@Formosa様\n初回の打合せ。\n");
    assert_eq!(
        fs::read_to_string(dir.path().join(id)).unwrap(),
        "@Formosa様\n初回の打合せ。\n"
    );

    // applying twice must not duplicate anything
    let again = session.apply_tags(id.to_string(), vec!["Formosa様".to_string()]).unwrap().body;
    assert_eq!(again, updated);

    // the index knows about the new tag straight away, and the tag is no longer suggested
    assert!(session.tags().iter().any(|t| t.tag == "Formosa様"));
    let offered = tags_of(&session, id);
    assert!(!offered.contains(&"Formosa様".to_string()), "{offered:?}");

    // a second tag goes after the first, before the trailing spaces
    let two = session
        .apply_tags(id.to_string(), vec!["お客様打合せ".to_string()])
        .unwrap()
        .body;
    assert_eq!(two, "@Formosa様 @お客様打合せ\n初回の打合せ。\n");
}

#[test]
fn applying_a_tag_to_a_heading_note_puts_the_tag_line_on_top() {
    let (dir, session) = vault();
    let id = "Figma 261015.md";
    let updated = session.apply_tags(id.to_string(), vec!["デザイン".to_string()]).unwrap().body;
    assert_eq!(updated, "@Figma @デザイン\n- コンポーネント整理\n");
    assert!(dir.path().join(id).is_file());
}
