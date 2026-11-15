//! Minimal Markdown parsing for native rendering.
//!
//! The core does NOT produce HTML. It produces a token stream that the
//! native UI (NSTextView / Compose TextField) renders directly.

#[derive(Debug, Clone, PartialEq)]
pub enum Block {
    Blank,
    Heading {
        level: u8,
        text: String,
        line: u32,
    },
    ListItem {
        indent: u8,
        ordered: bool,
        checked: Option<bool>,
        text: String,
        line: u32,
    },
    Quote {
        text: String,
        line: u32,
    },
    Image {
        src: String,
        alt: String,
        line: u32,
    },
    Code {
        lang: String,
        text: String,
        line: u32,
    },
    Paragraph {
        text: String,
        line: u32,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum Inline {
    Text(String),
    Bold(String),
    Italic(String),
    Strike(String),
    Code(String),
    Image { src: String, alt: String },
    Link { text: String, url: String },
}

pub fn parse_blocks(src: &str) -> Vec<Block> {
    let mut out = Vec::new();
    let mut in_fence = false;
    let mut fence_lang = String::new();
    let mut fence_start = 0u32;
    let mut fence_buf = String::new();

    for (idx, raw) in src.split('\n').enumerate() {
        let line_no = idx as u32 + 1;
        let line = raw.trim_end_matches('\r');

        let trimmed = line.trim_start();

        if in_fence {
            if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
                in_fence = false;
                out.push(Block::Code {
                    lang: std::mem::take(&mut fence_lang),
                    text: std::mem::take(&mut fence_buf),
                    line: fence_start,
                });
            } else {
                fence_buf.push_str(line);
                fence_buf.push('\n');
            }
            continue;
        }

        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = true;
            fence_start = line_no;
            fence_lang = trimmed.trim_start_matches(['`', '~']).trim().to_string();
            continue;
        }

        if trimmed.is_empty() {
            out.push(Block::Blank);
            continue;
        }

        // heading
        let hashes = trimmed.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) {
            let rest = &trimmed[hashes..];
            if rest.starts_with(' ') || rest.is_empty() {
                out.push(Block::Heading {
                    level: hashes as u8,
                    text: rest.trim_start().to_string(),
                    line: line_no,
                });
                continue;
            }
        }

        // quote
        if let Some(rest) = trimmed.strip_prefix("> ") {
            out.push(Block::Quote {
                text: rest.to_string(),
                line: line_no,
            });
            continue;
        }

        // list item
        let indent_chars = line.chars().take_while(|c| *c == ' ').count();
        let indent = (indent_chars / 2) as u8;
        let body = trimmed;
        let (is_item, ordered, after) = list_marker(body);
        if is_item {
            let (checked, rest) = checkbox(after);
            out.push(Block::ListItem {
                indent,
                ordered,
                checked,
                text: rest.trim().to_string(),
                line: line_no,
            });
            continue;
        }

        // standalone image line
        if let Some(img) = standalone_image(trimmed) {
            out.push(Block::Image {
                src: img.0,
                alt: img.1,
                line: line_no,
            });
            continue;
        }

        out.push(Block::Paragraph {
            text: trimmed.to_string(),
            line: line_no,
        });
    }

    if in_fence {
        out.push(Block::Code {
            lang: fence_lang,
            text: fence_buf,
            line: fence_start,
        });
    }
    out
}

fn list_marker(s: &str) -> (bool, bool, &str) {
    for m in ['-', '*', '+'] {
        if let Some(rest) = s.strip_prefix(m) {
            if rest.starts_with(' ') {
                return (true, false, &rest[1..]);
            }
        }
    }
    let digits = s.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits > 0 {
        let rest = &s[digits..];
        if let Some(r2) = rest.strip_prefix(". ") {
            return (true, true, r2);
        }
    }
    (false, false, s)
}

fn checkbox(s: &str) -> (Option<bool>, &str) {
    if let Some(r) = s.strip_prefix("[ ] ") {
        return (Some(false), r);
    }
    if let Some(r) = s.strip_prefix("[x] ").or_else(|| s.strip_prefix("[X] ")) {
        return (Some(true), r);
    }
    (None, s)
}

fn standalone_image(s: &str) -> Option<(String, String)> {
    let t = s.trim();
    if let Some(rest) = t.strip_prefix("![[") {
        if let Some(end) = rest.find("]]") {
            let inner = &rest[..end];
            let src = inner.split('|').next().unwrap_or(inner).to_string();
            return Some((src, String::new()));
        }
    }
    if let Some(rest) = t.strip_prefix("![") {
        if let Some(close) = rest.find("](") {
            let alt = rest[..close].to_string();
            let after = &rest[close + 2..];
            if let Some(end) = after.find(')') {
                return Some((after[..end].to_string(), alt));
            }
        }
    }
    None
}

/// Inline tokenizer. Supports `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``,
/// `![alt](src)`, `![[src]]`, `[text](url)`.
pub fn parse_inline(s: &str) -> Vec<Inline> {
    let mut out: Vec<Inline> = Vec::new();
    let mut buf = String::new();
    let mut i = 0usize;
    let b: Vec<char> = s.chars().collect();

    macro_rules! flush {
        () => {
            if !buf.is_empty() {
                out.push(Inline::Text(std::mem::take(&mut buf)));
            }
        };
    }

    while i < b.len() {
        // image / link
        if b[i] == '!' && i + 1 < b.len() && b[i + 1] == '[' {
            if let Some((tok, next)) = parse_embed(&b, i) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        if b[i] == '[' {
            if let Some((tok, next)) = parse_link(&b, i) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        if b[i] == '`' {
            if let Some((tok, next)) = parse_delimited(&b, i, '`', '`', |v| Inline::Code(v)) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        if b[i] == '~' && i + 1 < b.len() && b[i + 1] == '~' {
            if let Some((tok, next)) = parse_delimited(&b, i + 2, '~', '~', |v| Inline::Strike(v)) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        if b[i] == '*' && i + 1 < b.len() && b[i + 1] == '*' {
            if let Some((tok, next)) = parse_delimited(&b, i + 2, '*', '*', |v| Inline::Bold(v)) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        if b[i] == '*' {
            if let Some((tok, next)) = parse_delimited(&b, i + 1, '*', '*', |v| Inline::Italic(v)) {
                flush!();
                out.push(tok);
                i = next;
                continue;
            }
        }
        buf.push(b[i]);
        i += 1;
    }
    flush!();
    out
}

fn parse_delimited(
    b: &[char],
    start: usize,
    open: char,
    close: char,
    wrap: impl Fn(String) -> Inline,
) -> Option<(Inline, usize)> {
    if b.get(start) == Some(&open) {
        return None; // empty span
    }
    let mut j = start;
    while j < b.len() {
        if b[j] == close {
            let inner: String = b[start..j].iter().collect();
            if !inner.is_empty() {
                return Some((wrap(inner), j + 1));
            }
            return None;
        }
        j += 1;
    }
    None
}

fn parse_embed(b: &[char], i: usize) -> Option<(Inline, usize)> {
    // ![[src]] or ![[src|300]]
    let s: String = b[i..].iter().collect();
    if let Some(rest) = s.strip_prefix("![[") {
        if let Some(end) = rest.find("]]") {
            let inner = &rest[..end];
            let src = inner.split('|').next().unwrap_or(inner).to_string();
            let consumed = 3 + end + 2;
            return Some((
                Inline::Image {
                    src,
                    alt: String::new(),
                },
                i + consumed,
            ));
        }
        return None;
    }
    // ![alt](src)
    let rest = s.strip_prefix("![")?;
    let close = rest.find("](")?;
    let alt = rest[..close].to_string();
    let after = &rest[close + 2..];
    let end = after.find(')')?;
    let src = after[..end].to_string();
    let consumed = 3 + close + 2 + end + 1;
    Some((Inline::Image { src, alt }, i + consumed))
}

fn parse_link(b: &[char], i: usize) -> Option<(Inline, usize)> {
    let s: String = b[i..].iter().collect();
    let rest = s.strip_prefix('[')?;
    let close = rest.find("](")?;
    let text = rest[..close].to_string();
    let after = &rest[close + 2..];
    let end = after.find(')')?;
    let url = after[..end].to_string();
    let consumed = 1 + close + 2 + end + 1;
    Some((Inline::Link { text, url }, i + consumed))
}

/// All image sources referenced in the document (both syntaxes).
pub fn image_sources(src: &str) -> Vec<String> {
    let mut out = Vec::new();
    for block in parse_blocks(src) {
        if let Block::Image { src, .. } = block {
            out.push(src);
        }
    }
    for inline in parse_inline(src) {
        if let Inline::Image { src, .. } = inline {
            out.push(src);
        }
    }
    out.sort();
    out.dedup();
    out
}
