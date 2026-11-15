//! Editor assists shared by both platforms.
//!
//! The *decisions* live here (pure functions, unit-tested) so macOS and Android
//! behave identically; each UI only wires key events and renders the candidates.

use crate::search::{normalize, Index};

/// What to do when the user presses Return at the end of `line`.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ListAction {
    /// Insert a newline and this marker.
    Continue { marker: String },
    /// The current item is empty: replace the marker on this line with `marker`
    /// (an empty string ends the list, a shorter one outdents a level).
    Replace { marker: String },
    /// Not a list item.
    None,
}

/// Marker continuation for `- `, `* `, `+ `, `1. `, `- [ ] `, `- [x] ` and `> `.
pub fn list_action(line: &str) -> ListAction {
    let indent: String = line.chars().take_while(|c| *c == ' ' || *c == '\t').collect();
    let rest = &line[indent.len()..];

    if let Some(after) = rest.strip_prefix("> ") {
        if after.trim().is_empty() {
            return outdent(&indent, "> ");
        }
        return ListAction::Continue { marker: format!("{indent}> ") };
    }

    for bullet in ['-', '*', '+'] {
        let Some(after) = rest.strip_prefix(bullet) else { continue };
        let Some(after_space) = after.strip_prefix(' ') else { continue };
        let (checked, body) = split_checkbox(after_space);
        let bare = if checked.is_some() {
            format!("{bullet} [ ] ")
        } else {
            format!("{bullet} ")
        };
        if body.trim().is_empty() {
            return outdent(&indent, &bare);
        }
        return ListAction::Continue { marker: format!("{indent}{bare}") };
    }

    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() {
        if let Some(after) = rest[digits.len()..].strip_prefix(". ") {
            if after.trim().is_empty() {
                return outdent(&indent, &format!("{digits}. "));
            }
            let next = digits.parse::<u32>().unwrap_or(1) + 1;
            return ListAction::Continue { marker: format!("{indent}{next}. ") };
        }
    }

    ListAction::None
}

/// An empty item loses one indent step; at the left margin the marker goes away.
fn outdent(indent: &str, marker: &str) -> ListAction {
    let shallower = if let Some(rest) = indent.strip_suffix("  ") {
        rest
    } else if let Some(rest) = indent.strip_suffix('\t') {
        rest
    } else if let Some(rest) = indent.strip_suffix(' ') {
        rest
    } else {
        ""
    };

    if shallower.len() == indent.len() {
        // no indentation to remove: leave the list entirely
        return ListAction::Replace { marker: String::new() };
    }
    ListAction::Replace { marker: format!("{shallower}{marker}") }
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

/// Block styles the editor toolbar can apply to the current line.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum BlockKind {
    Bullet,
    Ordered,
    Task,
    Heading,
    Quote,
}

#[derive(Debug, Clone, PartialEq)]
enum LineKind {
    Plain,
    Bullet(char),
    Ordered(u32),
    Task,
    Heading(u8),
    Quote,
}

struct ParsedLine {
    indent: String,
    kind: LineKind,
    checked: Option<bool>,
    content: String,
}

fn parse_line(line: &str) -> ParsedLine {
    let indent: String = line.chars().take_while(|c| *c == ' ' || *c == '\t').collect();
    let rest = &line[indent.len()..];

    let base = ParsedLine {
        indent: indent.clone(),
        kind: LineKind::Plain,
        checked: None,
        content: rest.to_string(),
    };

    // heading
    let hashes = rest.chars().take_while(|c| *c == '#').count();
    if (1..=6).contains(&hashes) {
        let after = &rest[hashes..];
        if let Some(text) = after.strip_prefix(' ') {
            return ParsedLine {
                indent,
                kind: LineKind::Heading(hashes as u8),
                checked: None,
                content: text.to_string(),
            };
        }
    }

    // quote
    if let Some(text) = rest.strip_prefix("> ") {
        return ParsedLine { indent, kind: LineKind::Quote, checked: None, content: text.to_string() };
    }

    // task / bullet
    for bullet in ['-', '*', '+'] {
        if let Some(after) = rest.strip_prefix(bullet) {
            if let Some(after_space) = after.strip_prefix(' ') {
                if let Some((checked, body)) = task_state(after_space) {
                    return ParsedLine {
                        indent,
                        kind: LineKind::Task,
                        checked: Some(checked),
                        content: body.to_string(),
                    };
                }
                if let Some(body) = after_space.strip_prefix("[ ] ").or(after_space.strip_prefix("[x] ")) {
                    return ParsedLine {
                        indent,
                        kind: LineKind::Task,
                        checked: Some(false),
                        content: body.to_string(),
                    };
                }
                return ParsedLine {
                    indent,
                    kind: LineKind::Bullet(bullet),
                    checked: None,
                    content: after_space.to_string(),
                };
            }
        }
    }

    // ordered
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() {
        if let Some(body) = rest[digits.len()..].strip_prefix(". ") {
            return ParsedLine {
                indent,
                kind: LineKind::Ordered(digits.parse().unwrap_or(1)),
                checked: None,
                content: body.to_string(),
            };
        }
    }

    base
}

fn task_state(s: &str) -> Option<(bool, &str)> {
    if let Some(r) = s.strip_prefix("[ ] ") {
        return Some((false, r));
    }
    if let Some(r) = s.strip_prefix("[x] ").or_else(|| s.strip_prefix("[X] ")) {
        return Some((true, r));
    }
    None
}

fn marker_of(kind: &BlockKind) -> &'static str {
    match kind {
        BlockKind::Bullet => "- ",
        BlockKind::Ordered => "1. ",
        BlockKind::Task => "- [ ] ",
        BlockKind::Heading => "# ",
        BlockKind::Quote => "> ",
    }
}

fn matches(parsed: &ParsedLine, kind: &BlockKind) -> bool {
    matches!(
        (&parsed.kind, kind),
        (LineKind::Bullet(_), BlockKind::Bullet)
            | (LineKind::Ordered(_), BlockKind::Ordered)
            | (LineKind::Task, BlockKind::Task)
            | (LineKind::Heading(_), BlockKind::Heading)
            | (LineKind::Quote, BlockKind::Quote)
    )
}

/// Replace the block marker on this line. Pressing the button for the block the
/// line already uses removes the marker instead, so the buttons behave as toggles.
pub fn format_block(line: &str, kind: BlockKind) -> String {
    let parsed = parse_line(line);
    if matches(&parsed, &kind) {
        return format!("{}{}", parsed.indent, parsed.content);
    }
    format!("{}{}{}", parsed.indent, marker_of(&kind), parsed.content)
}

/// Flip a task checkbox, converting a non-task line into an unchecked task.
pub fn toggle_task(line: &str) -> String {
    let parsed = parse_line(line);
    if let (LineKind::Task, Some(checked)) = (&parsed.kind, parsed.checked) {
        let mark = if checked { "[ ]" } else { "[x]" };
        return format!("{}- {mark} {}", parsed.indent, parsed.content);
    }
    format!("{}- [ ] {}", parsed.indent, parsed.content)
}

/// Result of a text transform, with the selection expressed in **characters**
/// (each UI converts to its own UTF-16 offsets).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ToggleResult {
    pub text: String,
    pub sel_start: u32,
    pub sel_end: u32,
}

/// Wrap or unwrap the selection with an inline marker such as `**`.
///
/// Pressing the button twice must return to the original text:
/// - selection already wrapped, or markers just outside it -> remove them
/// - no selection but the caret sits inside a marked span -> remove the pair
/// - otherwise -> insert the marker pair (caret between them when nothing is selected)
pub fn toggle_inline(text: &str, sel_start: u32, sel_end: u32, mark: &str) -> ToggleResult {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    let mut start = (sel_start as usize).min(len);
    let mut end = (sel_end as usize).min(len);
    if start > end {
        std::mem::swap(&mut start, &mut end);
    }

    let m: Vec<char> = mark.chars().collect();
    let mlen = m.len();
    let slice_matches = |from: usize, to: usize| -> bool {
        if to > len || to - from != mlen {
            return false;
        }
        chars[from..to] == m[..]
    };

    // 1) selection includes the markers: "**foo**" -> "foo"
    if start != end && end - start >= 2 * mlen && slice_matches(start, start + mlen) && slice_matches(end - mlen, end) {
        let mut out: String = chars[..start].iter().collect();
        out.extend(&chars[start + mlen..end - mlen]);
        out.extend(&chars[end..]);
        let sel = start;
        let content_len = end - start - 2 * mlen;
        return ToggleResult { text: out, sel_start: sel as u32, sel_end: (sel + content_len) as u32 };
    }

    // 2) markers just outside the selection (or around the caret)
    let around = if start == end {
        // find the enclosing pair on this line
        let line_start = chars[..start].iter().rposition(|c| *c == '\n').map(|i| i + 1).unwrap_or(0);
        let line_end = chars[start..].iter().position(|c| *c == '\n').map(|i| start + i).unwrap_or(len);
        let before = (line_start..start).rev().find(|i| *i >= line_start && *i + mlen <= start && slice_matches(*i, *i + mlen));
        match before {
            Some(open) => {
                let close = (start..line_end).find(|i| *i + mlen <= line_end && slice_matches(*i, *i + mlen));
                close.map(|c| (open, c))
            }
            None => None,
        }
    } else if start >= mlen && end + mlen <= len && slice_matches(start - mlen, start) && slice_matches(end, end + mlen) {
        Some((start - mlen, end))
    } else {
        None
    };

    if let Some((open, close)) = around {
        let mut out: String = chars[..open].iter().collect();
        out.extend(&chars[open + mlen..close]);
        out.extend(&chars[close + mlen..]);
        let shift_before = (start - open).min(mlen);
        let new_start = start - shift_before;
        let new_end = (end - mlen).max(new_start);
        return ToggleResult { text: out, sel_start: new_start as u32, sel_end: new_end as u32 };
    }

    // 3) wrap
    let mut out: String = chars[..start].iter().collect();
    out.push_str(mark);
    out.extend(&chars[start..end]);
    out.push_str(mark);
    out.extend(&chars[end..]);

    if start == end {
        ToggleResult { text: out, sel_start: (start + mlen) as u32, sel_end: (start + mlen) as u32 }
    } else {
        ToggleResult { text: out, sel_start: start as u32, sel_end: (end + 2 * mlen) as u32 }
    }
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

/// Move a list line one level in (`outdent == false`) or out (`outdent == true`).
///
/// Returns the rewritten line, or `None` when the line is not a list item.
pub fn indent_list_line(line: &str, outdent: bool) -> Option<String> {
    let indent: String = line.chars().take_while(|c| *c == ' ' || *c == '\t').collect();
    let rest = &line[indent.len()..];

    let is_list = rest.starts_with("> ")
        || ['-', '*', '+']
            .iter()
            .any(|b| rest.starts_with(&format!("{b} ")))
        || rest
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .count()
            .gt(&0)
            && rest
                .chars()
                .skip_while(|c| c.is_ascii_digit())
                .collect::<String>()
                .starts_with(". ");

    if !is_list {
        return None;
    }

    let new_indent = if outdent {
        if let Some(r) = indent.strip_suffix("  ") {
            r.to_string()
        } else if let Some(r) = indent.strip_suffix('\t') {
            r.to_string()
        } else if let Some(r) = indent.strip_suffix(' ') {
            r.to_string()
        } else {
            indent.clone()
        }
    } else {
        format!("{indent}  ")
    };

    Some(format!("{new_indent}{rest}"))
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
