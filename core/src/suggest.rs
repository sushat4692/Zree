//! Tag suggestions built from structure alone.
//!
//! No network and no model: the same note always yields the same list, which is what lets
//! macOS and Android agree and lets the rules be tested. The signals, in the order they earn
//! their weight on the author's vault (375 notes, 151 tagged):
//!
//! | signal | weight | tier | precision measured |
//! |---|---|---|---|
//! | an existing tag is a whole token of the title | 3.0 | 1 | 100% |
//! | a sibling note (same customer) carries the tag | 2.5 x ratio | 1 | 100% |
//! | the title names a customer (`〜様`) | 3.0 | 1 | 95% |
//! | the tag co-occurs with a tag already on the note | 2.5 x ratio | 1 | 87% |
//! | the tag appears inside a longer title token | 2.0 | 2 | 79% |
//! | the tag is mentioned in the body | 2.0 max | 2 | 85% |
//! | a second customer in the title | 2.0 | 2 | 77% |
//! | same-day siblings | 2.0 x ratio | 2 | 71% |
//!
//! Tier 1 is shown straight away; tier 2 hides behind "other candidates".

use crate::search::{normalize, Entry, Index};
use crate::tags;
use std::collections::{HashMap, HashSet};

/// Suggestions below this score are dropped.
///
/// 2.5 sits above every weak rule's standalone weight (body mention 1.5, title substring 2.0,
/// second customer 2.0, same-day sibling 2.0), so those only appear when a second signal
/// agrees. Measured on the vault: precision 90% at this threshold, 56% at 2.0.
pub const TAU: f32 = 2.5;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Reason {
    /// `〜様` in the title, first customer named.
    Customer,
    /// `〜様` in the title, after another customer.
    CustomerSecondary,
    /// An existing tag is a whole token of the title.
    TitleExact,
    /// An existing tag is part of a longer title token.
    TitleSubstring,
    /// The tag is written in the body.
    BodyMention,
    /// Another note about the same customer carries this tag.
    Sibling,
    /// Another note from the same day carries this tag.
    SiblingDate,
    /// The tag usually appears together with one already on this note.
    Cooccurrence,
}

impl Reason {
    pub fn tier(self) -> u8 {
        match self {
            Reason::Customer
            | Reason::TitleExact
            | Reason::Sibling
            | Reason::Cooccurrence => 1,
            Reason::CustomerSecondary
            | Reason::TitleSubstring
            | Reason::BodyMention
            | Reason::SiblingDate => 2,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Reason::Customer => "customer",
            Reason::CustomerSecondary => "customer2",
            Reason::TitleExact => "title-exact",
            Reason::TitleSubstring => "title-sub",
            Reason::BodyMention => "body-mention",
            Reason::Sibling => "sibling",
            Reason::SiblingDate => "sibling-date",
            Reason::Cooccurrence => "cooccur",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Suggestion {
    pub tag: String,
    pub score: f32,
    pub tier: u8,
    pub reasons: Vec<Reason>,
}

/// Everything the rules need to know about the vault, built once per index.
#[derive(Debug, Default, Clone)]
pub struct Vocabulary {
    /// normalised tag -> number of notes carrying it
    pub counts: HashMap<String, u32>,
    /// normalised tag -> the spelling most notes use
    pub display: HashMap<String, String>,
    /// normalised tag -> tags that share a note with it, most frequent first
    pub cooccur: HashMap<String, Vec<(String, u32)>>,
    /// normalised customer name -> entry indexes
    pub by_customer: HashMap<String, Vec<usize>>,
    /// date token -> entry indexes
    pub by_date: HashMap<String, Vec<usize>>,
}

impl Vocabulary {
    pub fn build(entries: &[Entry]) -> Self {
        let mut counts: HashMap<String, u32> = HashMap::new();
        let mut spellings: HashMap<String, HashMap<String, u32>> = HashMap::new();

        for entry in entries {
            for tag in unique_keys(&entry.meta.tags) {
                *counts.entry(tag.clone()).or_insert(0) += 1;
            }
            for tag in &entry.meta.tags {
                *spellings
                    .entry(normalize(tag))
                    .or_default()
                    .entry(tag.clone())
                    .or_insert(0) += 1;
            }
        }

        let display = spellings
            .into_iter()
            .map(|(key, forms)| {
                let mut best: Vec<(String, u32)> = forms.into_iter().collect();
                // most used spelling wins; ties fall back to the lexical order so both
                // platforms print the same one
                best.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
                (key, best[0].0.clone())
            })
            .collect();

        let mut cooccur: HashMap<String, HashMap<String, u32>> = HashMap::new();
        for entry in entries {
            let keys = unique_keys(&entry.meta.tags);
            for a in &keys {
                for b in &keys {
                    if a != b {
                        *cooccur.entry(a.clone()).or_default().entry(b.clone()).or_insert(0) += 1;
                    }
                }
            }
        }
        let cooccur = cooccur
            .into_iter()
            .map(|(key, partners)| {
                let mut list: Vec<(String, u32)> = partners.into_iter().collect();
                list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
                list.truncate(8);
                (key, list)
            })
            .collect();

        let mut by_customer: HashMap<String, Vec<usize>> = HashMap::new();
        let mut by_date: HashMap<String, Vec<usize>> = HashMap::new();
        for (index, entry) in entries.iter().enumerate() {
            for customer in customers(&entry.meta.title) {
                by_customer.entry(normalize(&customer)).or_default().push(index);
            }
            for date in dates(&entry.meta.title) {
                by_date.entry(date).or_default().push(index);
            }
        }

        Vocabulary { counts, display, cooccur, by_customer, by_date }
    }

    /// The spelling the vault already uses for this tag, if any.
    pub fn display_of(&self, tag: &str) -> Option<&str> {
        self.display.get(&normalize(tag)).map(|s| s.as_str())
    }
}

/// Suggestions for one note. `existing` are the tags already written on it; they are never
/// offered again. Deterministic: score, then frequency, then the tag itself.
pub fn suggest(
    index: &Index,
    exclude_id: &str,
    title: &str,
    body: &str,
    existing: &[String],
    limit: usize,
) -> Vec<Suggestion> {
    let vocab = &index.vocab;
    let taken: HashSet<String> = unique_keys(existing).into_iter().collect();

    // key -> (score, reasons, spelling to show)
    let mut acc: HashMap<String, (f32, Vec<Reason>, String)> = HashMap::new();
    let mut add = |tag: &str, score: f32, reason: Reason| {
        // a new tag keeps the spelling the title used; an existing one borrows the vault's
        let key = normalize(tag);
        if key.is_empty() || taken.contains(&key) {
            return;
        }
        // an existing tag is shown the way the vault spells it; a new one (a customer name
        // straight from the title) keeps the author's capitalisation
        let shown = vocab.display_of(&key).map(|s| s.to_string()).unwrap_or_else(|| tag.to_string());
        let slot = acc.entry(key).or_insert_with(|| (0.0, Vec::new(), shown));
        slot.0 += score;
        if !slot.1.contains(&reason) {
            slot.1.push(reason);
        }
    };

    let tokens = title_tokens(title);
    let token_keys: HashSet<String> = tokens.iter().map(|t| normalize(t)).collect();
    let title_norm = normalize(title);
    let body_norm = normalize(&tags::strip(body));

    for (position, customer) in customers(title).iter().enumerate() {
        let canonical = vocab.display_of(customer).unwrap_or(customer);
        add(
            canonical,
            if position == 0 { 3.0 } else { 2.0 },
            if position == 0 { Reason::Customer } else { Reason::CustomerSecondary },
        );
    }

    for (key, count) in &vocab.counts {
        if *count < 1 {
            continue;
        }
        let display = vocab.display_of(key).unwrap_or(key);
        if token_keys.contains(key) {
            add(display, 3.0, Reason::TitleExact);
        } else if !is_ascii(key) && title_norm.contains(key.as_str()) {
            add(display, 2.0, Reason::TitleSubstring);
        }
        let mentions = count_mentions(&body_norm, key);
        if mentions > 0 {
            add(display, (mentions.min(2) as f32) * 0.75, Reason::BodyMention);
        }
    }

    let (customer_siblings, date_siblings) = siblings(index, exclude_id, title);
    score_siblings(vocab, index, &customer_siblings, 2.5, Reason::Sibling, &mut add);
    if customer_siblings.is_empty() {
        // the same day is a weak hint: it only speaks when no customer links the note
        score_siblings(vocab, index, &date_siblings, 2.0, Reason::SiblingDate, &mut add);
    }

    for tag in &unique_keys(existing) {
        let total = vocab.counts.get(tag).copied().unwrap_or(0).max(1);
        if let Some(partners) = vocab.cooccur.get(tag) {
            for (partner, count) in partners {
                let score = 2.5 * (*count as f32) / (total as f32);
                let display = vocab.display_of(partner).unwrap_or(partner);
                add(display, score, Reason::Cooccurrence);
            }
        }
    }

    let mut out: Vec<Suggestion> = acc
        .into_iter()
        .filter(|(_, (score, _, _))| *score >= TAU)
        .map(|(_, (score, reasons, shown))| Suggestion {
            tag: shown,
            score,
            tier: reasons.iter().map(|r| r.tier()).min().unwrap_or(2),
            reasons,
        })
        .collect();

    out.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| {
                let ca = vocab.counts.get(&normalize(&a.tag)).copied().unwrap_or(0);
                let cb = vocab.counts.get(&normalize(&b.tag)).copied().unwrap_or(0);
                cb.cmp(&ca)
            })
            .then_with(|| a.tag.cmp(&b.tag))
    });
    out.truncate(limit);
    out
}

/// Add tags to a note, keeping the author's layout: the tag line stays first, and the two
/// trailing spaces that make a hard line break survive.
pub fn insert_tags(body: &str, tags: &[String]) -> String {
    let present: HashSet<String> = unique_keys(&crate::tags::extract(body)).into_iter().collect();
    let mut add: Vec<String> = Vec::new();
    for tag in tags {
        let clean = tag.trim().trim_start_matches('@');
        if clean.is_empty() {
            continue;
        }
        let key = normalize(clean);
        if present.contains(&key) || add.iter().any(|t| normalize(t) == key) {
            continue;
        }
        add.push(clean.to_string());
    }
    if add.is_empty() {
        return body.to_string();
    }

    let joined = add.iter().map(|t| format!("@{t}")).collect::<Vec<_>>().join(" ");
    let (first, rest) = match body.split_once('\n') {
        Some((first, rest)) => (first, rest),
        None => (body, ""),
    };
    let newline = if first.ends_with('\r') { "\r\n" } else { "\n" };

    if tags::is_tag_line(first) {
        let content = first.trim_end_matches([' ', '\t', '\r']);
        let trailing = &first[content.len()..];
        let separator = if content.trim().is_empty() { "" } else { " " };
        format!("{content}{separator}{joined}{trailing}{newline}{rest}")
    } else if first.is_empty() && rest.is_empty() {
        format!("{joined}{newline}")
    } else {
        format!("{joined}{newline}{first}{newline}{rest}")
    }
}

// ---------------------------------------------------------------- helpers

fn unique_keys(tags: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for tag in tags {
        let key = normalize(tag);
        if !key.is_empty() && seen.insert(key.clone()) {
            out.push(key);
        }
    }
    out
}

fn is_ascii(key: &str) -> bool {
    key.chars().all(|c| c.is_ascii())
}

/// ASCII tags need word boundaries (`PR` must not match `ProPhit`, `LH` not `LH&c`);
/// Japanese has no separators, so a substring is the only sensible test there.
fn count_mentions(haystack: &str, needle: &str) -> usize {
    if needle.is_empty() {
        return 0;
    }
    if !is_ascii(needle) {
        return haystack.matches(needle).count();
    }
    let bytes = haystack.as_bytes();
    let mut count = 0;
    let mut at = 0;
    while let Some(found) = haystack[at..].find(needle) {
        let start = at + found;
        let end = start + needle.len();
        let before_ok = start == 0 || !is_word_byte(bytes[start - 1]);
        let after_ok = end >= bytes.len() || !is_word_byte(bytes[end]);
        if before_ok && after_ok {
            count += 1;
        }
        at = start + needle.len().max(1);
    }
    count
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'&'
}

const CUSTOMER_STOP: &[&str] = &["お客様", "御客様", "皆様", "様"];

/// Words of a title, with dates blanked out so `240604` never becomes part of a name.
fn title_tokens(title: &str) -> Vec<String> {
    let cleaned = blank_dates(title);
    cleaned
        .split(|c: char| {
            c.is_whitespace()
                || matches!(
                    c,
                    '・' | '／' | '/' | '、' | '，' | ',' | '(' | ')' | '（' | '）' | '[' | ']'
                        | '【' | '】' | '「' | '」' | '：' | ':'
                )
        })
        .filter(|t| !t.is_empty())
        .map(|t| t.trim().to_string())
        .collect()
}

fn customers(title: &str) -> Vec<String> {
    let tokens = title_tokens(title);
    let mut out: Vec<String> = Vec::new();
    for (index, token) in tokens.iter().enumerate() {
        let looks_customer = token.ends_with('様')
            && token.chars().count() >= 3
            && !CUSTOMER_STOP.contains(&token.as_str());
        if !looks_customer {
            continue;
        }
        // `Absolute Design様`: the name is Latin words with spaces in it
        let mut name = token.clone();
        let mut at = index;
        while at > 0 {
            let previous = tokens[at - 1].as_str();
            let latin = !previous.is_empty()
                && previous.chars().all(|c| c.is_ascii() && (c.is_alphanumeric() || "&.-".contains(c)));
            if latin && !previous.chars().all(|c| c.is_ascii_digit()) {
                name = format!("{previous} {name}");
                at -= 1;
            } else {
                break;
            }
        }
        out.push(name);
    }
    out
}

fn dates(title: &str) -> Vec<String> {
    let chars: Vec<char> = title.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if !chars[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let start = i;
        let mut separators = 0;
        while i < chars.len() && (chars[i].is_ascii_digit() || "-/.".contains(chars[i])) {
            if "-/.".contains(chars[i]) {
                separators += 1;
            }
            i += 1;
        }
        let run: String = chars[start..i].iter().collect();
        let digits = run.chars().filter(|c| c.is_ascii_digit()).count();
        let date_like = (separators >= 2 && digits >= 6) || (separators == 0 && (5..=8).contains(&digits));
        if date_like {
            out.push(run);
        }
    }
    out
}

fn blank_dates(title: &str) -> String {
    let mut out = String::with_capacity(title.len());
    for token in title.split_inclusive(|c: char| c.is_whitespace()) {
        let trimmed = token.trim_end();
        let digits = trimmed.chars().filter(|c| c.is_ascii_digit()).count();
        let others = trimmed.chars().all(|c| c.is_ascii_digit() || "-/.".contains(c));
        if !trimmed.is_empty() && others && digits >= 5 {
            out.push_str(&" ".repeat(trimmed.chars().count()));
            out.push_str(&token[trimmed.len()..]);
        } else {
            out.push_str(token);
        }
    }
    out
}

/// Notes about the same customer, and notes from the same day. Both exclude the note itself.
fn siblings(index: &Index, exclude_id: &str, title: &str) -> (Vec<usize>, Vec<usize>) {
    let mut customer_hits = Vec::new();
    for customer in customers(title) {
        if let Some(list) = index.vocab.by_customer.get(&normalize(&customer)) {
            customer_hits.extend(list.iter().copied());
        }
    }
    let customer_hits: Vec<usize> = dedupe(
        customer_hits
            .into_iter()
            .filter(|i| index.entries[*i].meta.id != exclude_id)
            .collect(),
    );

    let mut date_hits = Vec::new();
    for date in dates(title) {
        if let Some(list) = index.vocab.by_date.get(&date) {
            date_hits.extend(list.iter().copied());
        }
    }
    let date_hits: Vec<usize> = dedupe(
        date_hits
            .into_iter()
            .filter(|i| index.entries[*i].meta.id != exclude_id)
            .collect(),
    );

    (customer_hits, date_hits)
}

fn dedupe(mut list: Vec<usize>) -> Vec<usize> {
    list.sort_unstable();
    list.dedup();
    list.truncate(50);
    list
}

fn score_siblings(
    vocab: &Vocabulary,
    index: &Index,
    siblings: &[usize],
    weight: f32,
    reason: Reason,
    add: &mut impl FnMut(&str, f32, Reason),
) {
    if siblings.is_empty() {
        return;
    }
    let mut tally: HashMap<String, u32> = HashMap::new();
    for entry_index in siblings {
        for key in unique_keys(&index.entries[*entry_index].meta.tags) {
            *tally.entry(key).or_insert(0) += 1;
        }
    }
    let total = siblings.len() as f32;
    let mut ranked: Vec<(String, u32)> = tally.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    for (key, count) in ranked.into_iter().take(6) {
        let display = vocab.display_of(&key).unwrap_or(&key).to_string();
        add(&display, weight * (count as f32) / total, reason);
    }
}

/// Suggestions for a note already in the index.
pub fn suggest_for(index: &Index, id: &str, limit: usize) -> Vec<Suggestion> {
    match index.entries.iter().find(|e| e.meta.id == id) {
        Some(entry) => suggest(index, id, &entry.meta.title, &entry.body, &entry.meta.tags, limit),
        None => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insertion_keeps_the_tag_line_and_its_trailing_spaces() {
        let body = "@挨拶  \n本文\n";
        assert_eq!(insert_tags(body, &["新規".into()]), "@挨拶 @新規  \n本文\n");

        let body = "@1on1  @Dell @マネジメント\n- 議題\n";
        assert_eq!(
            insert_tags(body, &["LHc".into()]),
            "@1on1  @Dell @マネジメント @LHc\n- 議題\n"
        );
    }

    #[test]
    fn insertion_adds_a_line_ahead_of_a_heading() {
        let body = "# AI活用\n本文\n";
        assert_eq!(insert_tags(body, &["AI".into()]), "@AI\n# AI活用\n本文\n");
    }

    #[test]
    fn insertion_never_duplicates_or_repeats_the_at_sign() {
        let body = "@挨拶\n本文\n";
        assert_eq!(insert_tags(body, &["挨拶".into(), "@挨拶".into()]), body);
        assert_eq!(insert_tags(body, &["@新規".into(), "新規".into()]), "@挨拶 @新規\n本文\n");
    }

    #[test]
    fn insertion_copes_with_an_empty_note() {
        assert_eq!(insert_tags("", &["新規".into()]), "@新規\n");
    }

    #[test]
    fn customer_names_take_latin_words_but_not_dates() {
        assert_eq!(customers("Absolute Design様"), vec!["Absolute Design様"]);
        assert_eq!(customers("20260203 光電工様"), vec!["光電工様"]);
        assert_eq!(customers("CUBLIC様 クリマテック様"), vec!["CUBLIC様", "クリマテック様"]);
    }

    #[test]
    fn a_new_tag_keeps_the_capitalisation_of_the_title() {
        // the customer rule invents the tag, so there is no vault spelling to borrow
        let text = "Formosa様 230721";
        let tokens = title_tokens(text);
        assert_eq!(customers(text), vec!["Formosa様"]);
        assert!(tokens.iter().any(|t| t == "Formosa様"));
    }

    #[test]
    fn ascii_mentions_need_word_boundaries() {
        assert_eq!(count_mentions(&normalize("prophit の話"), "pr"), 0);
        assert_eq!(count_mentions(&normalize("lh&c 面談"), "lh"), 0);
        assert_eq!(count_mentions(&normalize("PR 施策"), "pr"), 1);
        assert_eq!(count_mentions(&normalize("マネジメントメモ"), "マネジメント"), 1);
    }
}
