//! Editor assists shared by both platforms.
//!
//! The *decisions* live here (pure functions, unit-tested) so macOS and Android
//! behave identically; each UI only wires key events and renders the candidates.

use crate::search::{normalize, Index};

/// What to do when the user presses Return at the end of `line`.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ListAction {
    /// Insert a new list marker after the newline.
    Continue { marker: String },
    /// The current item is empty: drop the marker instead of continuing.
    Remove { indent: u32 },
    /// Not a list item.
    None,
}

/// Marker continuation for `- `, `* `, `+ `, `1. `, `- [ ] `, `- [x] ` and `> `.
pub fn list_action(line: &str) -> ListAction {
    let indent_chars = line.chars().take_while(|c| *c == ' ' || *c == '\t').count();
    let indent_len = line[..indent_chars].chars().count();
    let indent: String = line.chars().take(indent_len).collect();
    let rest = &line[indent_len..];

    // blockquote
    if let Some(after) = rest.strip_prefix("> ") {
        if after.trim().is_empty() {
            return ListAction::Remove { indent: indent_len as u32 };
        }
        return ListAction::Continue { marker: format!("{indent}> ") };
    }

    // bullet, optionally a task checkbox
    for bullet in ['-', '*', '+'] {
        if let Some(after) = rest.strip_prefix(bullet) {
            let (boxed, body) = match after.strip_prefix(' ') {
                Some(b) => (false, b),
                None => continue,
            };
            let (checked, body) = split_checkbox(body);
            if body.trim().is_empty() && !boxed {
                return ListAction::Remove { indent: indent_len as u32 };
            }
            if body.trim().is_empty() && boxed {
                return ListAction::Remove { indent: indent_len as u32 };
            }
            let marker = if checked.is_some() {
                format!("{indent}{bullet} [ ] ")
            } else {
                format!("{indent}{bullet} ")
            };
            return ListAction::Continue { marker };
        }
    }

    // ordered list
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() {
        if let Some(after) = rest[digits.len()..].strip_prefix(". ") {
            if after.trim().is_empty() {
                return ListAction::Remove { indent: indent_len as u32 };
            }
            let next = digits.parse::<u32>().unwrap_or(1) + 1;
            return ListAction::Continue { marker: format!("{indent}{next}. ") };
        }
    }

    ListAction::None
}

fn split_checkbox(s: &str) -> (Option<bool>, &str) {
    if let Some(r) = s.strip_prefix("[ ] ") {
        return (Some(false), r);
    }
    if let Some(r) = s.strip_prefix("[x] ").or_else(|| s.strip_prefix("[X] ")) {
        return (Some(true), r);
    }
    (None, s)
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum CompletionKind {
    Tag,
    Note,
    NoteTarget,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NoteSuggestion {
    pub id: String,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CompletionContext {
    pub kind: CompletionKind,
    /// Text typed so far, without the trigger character. The UI replaces
    /// `cursor - prefix.length .. cursor` with the chosen candidate, so no
    /// byte/UTF-16 offset arithmetic is needed across the FFI boundary.
    pub prefix: String,
}

/// Decide whether the cursor sits in something completable.
///
/// `before_cursor` is the editor text up to the caret. Returns `None` inside
/// fenced code blocks, which is where `#` and `[` are just characters.
pub fn completion_context(before_cursor: &str) -> Option<CompletionContext> {
    let fence_count = before_cursor
        .lines()
        .filter(|l| l.trim_start().starts_with("```"))
        .count();
    if fence_count % 2 == 1 {
        return None;
    }

    let line_start = before_cursor.rfind('\n').map(|i| i + 1).unwrap_or(0);
    let line = &before_cursor[line_start..];

    // link target: ](foo
    if let Some(open) = line.rfind("](") {
        let prefix = &line[open + 2..];
        if !prefix.contains(')') && !prefix.contains(' ') {
            return Some(CompletionContext {
                kind: CompletionKind::NoteTarget,
                prefix: prefix.to_string(),
            });
        }
    }

    // link label: [foo
    if let Some(open) = line.rfind('[') {
        let prefix = &line[open + 1..];
        if !prefix.contains(']') {
            return Some(CompletionContext {
                kind: CompletionKind::Note,
                prefix: prefix.to_string(),
            });
        }
    }

    // inline tag: #foo / ＃foo (Japanese IMEs produce the full-width form)
    if let Some((hash, marker)) = line
        .char_indices()
        .rev()
        .find(|(_, c)| *c == '#' || *c == '＃')
    {
        let after = hash + marker.len_utf8();
        let before = &line[..hash];
        // Japanese IMEs swallow the space after a list marker, so "-#tag" is a
        // realistic thing to type; treat markers and opening punctuation as a
        // word boundary too.
        let at_boundary = before.is_empty()
            || before.ends_with(char::is_whitespace)
            || matches!(
                before.chars().next_back(),
                Some('-' | '*' | '+' | '>' | '[' | '(' | '/' | '、' | '。' | '「' | '（')
            );
        let prefix = &line[after..];
        let clean = !prefix.contains(' ')
            && !prefix.contains('　')
            && !prefix.contains('#')
            && !prefix.contains('＃');
        if at_boundary && clean {
            return Some(CompletionContext {
                kind: CompletionKind::Tag,
                prefix: prefix.to_string(),
            });
        }
    }

    None
}

impl Index {
    /// Tags starting with `prefix` (normalised, case/width insensitive).
    pub fn suggest_tags(&self, prefix: &str, limit: usize) -> Vec<String> {
        let needle = normalize(prefix.trim_start_matches('#'));
        let mut out: Vec<(String, u32)> = self
            .tags()
            .into_iter()
            .filter(|t| needle.is_empty() || normalize(&t.tag).starts_with(&needle))
            .map(|t| (t.tag, t.count))
            .collect();
        out.truncate(limit);
        out.into_iter().map(|(t, _)| t).collect()
    }

    /// Note titles starting with `prefix`, most recently modified first.
    pub fn suggest_notes(&self, prefix: &str, limit: usize) -> Vec<NoteSuggestion> {
        let needle = normalize(prefix.trim_start_matches('['));
        let mut hits: Vec<(String, String, i64)> = self
            .entries
            .iter()
            .filter(|e| needle.is_empty() || normalize(&e.meta.title).starts_with(&needle))
            .map(|e| (e.meta.id.clone(), e.meta.title.clone(), e.meta.mtime_ms))
            .collect();
        hits.sort_by(|a, b| b.2.cmp(&a.2).then(a.1.cmp(&b.1)));
        hits.truncate(limit);
        hits.into_iter()
            .map(|(id, title, _)| NoteSuggestion { id, title })
            .collect()
    }
}
