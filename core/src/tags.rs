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
    let mut in_fence = false;

    for raw_line in body.split('\n') {
        let line = raw_line.trim_end_matches('\r');

        // fenced code block tracking
        if line.trim_start().starts_with("```") || line.trim_start().starts_with("~~~") {
            in_fence = !in_fence;
            continue;
        }
        if in_fence {
            continue;
        }

        let chars: Vec<char> = line.chars().collect();
        let mut i = 0usize;
        while i < chars.len() {
            let c = chars[i];

            // skip inline code spans
            if c == '`' {
                let run = run_len(&chars, i, '`');
                i += run;
                // find matching run
                while i < chars.len() {
                    if chars[i] == '`' && run_len(&chars, i, '`') == run {
                        i += run;
                        break;
                    }
                    i += 1;
                }
                continue;
            }

            if c == '@' {
                let at_start = i == 0 || chars[i - 1].is_whitespace();
                if at_start {
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
                        if !out.iter().any(|t| t == &buf) {
                            out.push(buf);
                        }
                    }
                    i = j;
                    continue;
                }
            }
            i += 1;
        }
    }
    out
}

fn run_len(chars: &[char], at: usize, c: char) -> usize {
    let mut n = 0;
    while at + n < chars.len() && chars[at + n] == c {
        n += 1;
    }
    n
}

