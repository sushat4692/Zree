//! Tag extraction.
//!
//! Rules (shared by macOS and Android, documented in docs/spec.md):
//! * A tag starts with `@` at the start of a line or preceded by whitespace.
//! * The body ends at whitespace, another `@`, or a punctuation/terminator char.
//! * `#` is never a tag: it is the Markdown heading marker (`# `), and keeping the two
//!   apart is what lets a heading be typed while tag completion is active.
//! * Tags inside fenced code blocks and inline code spans are ignored.
//! * Only ASCII punctuation terminates a tag; CJK chars are valid tag body.

const TERMINATORS: &[char] = &[
    '、', '。', '，', '．', '！', '？', '「', '」', '『', '』', '（', '）', '【', '】', '〈', '〉',
    '《', '》', '・', '…', '—', '–', ',', '.', '!', '?', '"', '\'', '(', ')', '[', ']', '{', '}',
    '<', '>', '`', '|', '\\', '/', ';', ':', '*', '_', '~', '=', '+', '^', '$', '%', '&', '@',
];

/// Extract tags in first-seen order, de-duplicated.
pub fn extract(body: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for (_, tags) in scan(body) {
        for tag in tags {
            if !out.iter().any(|t| t == &tag) {
                out.push(tag);
            }
        }
    }
    out
}

/// The same document with every tag removed (spaces left in their place).
///
/// Used by tag suggestions: a tag that is already written on the first line must not count
/// as a mention of itself in the body.
pub fn strip(body: &str) -> String {
    let mut out = String::with_capacity(body.len());
    for (line, _) in scan(body) {
        out.push_str(&line);
        out.push('\n');
    }
    out.pop();
    out
}

/// True when the line holds nothing but tags and whitespace, e.g. `@1on1  @Dell`.
pub fn is_tag_line(line: &str) -> bool {
    let (stripped, tags) = scan_line(line.trim_end_matches('\r'), false);
    !tags.is_empty() && stripped.trim().is_empty()
}

/// Split a document into (line, tags found on it), honouring fences and inline code.
fn scan(body: &str) -> Vec<(String, Vec<String>)> {
    let mut out = Vec::new();
    let mut in_fence = false;
    for raw_line in body.split('\n') {
        let line = raw_line.trim_end_matches('\r');
        if line.trim_start().starts_with("```") || line.trim_start().starts_with("~~~") {
            in_fence = !in_fence;
            out.push((line.to_string(), Vec::new()));
            continue;
        }
        if in_fence {
            out.push((line.to_string(), Vec::new()));
            continue;
        }
        out.push(scan_line(line, true));
    }
    out
}

/// One line -> (line with tags blanked out, tags).
fn scan_line(line: &str, blank: bool) -> (String, Vec<String>) {
    let chars: Vec<char> = line.chars().collect();
    let mut kept = String::with_capacity(line.len());
    let mut tags = Vec::new();
    let mut i = 0usize;

    while i < chars.len() {
        let c = chars[i];

        // inline code spans are copied verbatim and never hold tags
        if c == '`' {
            let run = run_len(&chars, i, '`');
            let start = i;
            i += run;
            while i < chars.len() {
                if chars[i] == '`' && run_len(&chars, i, '`') == run {
                    i += run;
                    break;
                }
                i += 1;
            }
            for ch in &chars[start..i] {
                kept.push(*ch);
            }
            continue;
        }

        if c == '@' && (i == 0 || chars[i - 1].is_whitespace()) {
            let mut j = i + 1;
            let mut buf = String::new();
            while j < chars.len() {
                let ch = chars[j];
                if ch.is_whitespace() || ch == '@' || TERMINATORS.contains(&ch) {
                    break;
                }
                buf.push(ch);
                j += 1;
            }
            if !buf.is_empty() {
                tags.push(buf);
                if blank {
                    kept.push(' ');
                }
                i = j;
                continue;
            }
        }

        kept.push(c);
        i += 1;
    }

    (kept, tags)
}

fn run_len(chars: &[char], at: usize, c: char) -> usize {
    let mut n = 0;
    while at + n < chars.len() && chars[at + n] == c {
        n += 1;
    }
    n
}

