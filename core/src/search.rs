//! Japanese-friendly full-text search.
//!
//! Journaling notes are written without spaces, so tokenising on whitespace
//! is useless. We normalize (NFKC + lowercase) and do substring matching.
//! At this vault size (hundreds of notes, well under a few MB) a full scan is
//! instantaneous, so there is no index file to keep in sync.

use crate::error::NoteError;
use crate::vault::{NoteMeta, Vault};
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Hit {
    pub id: String,
    pub title: String,
    pub snippet: String,
    pub score: i32,
    pub tags: Vec<String>,
    pub mtime_ms: i64,
    pub created_ms: i64,
}

/// Order for the note list (search results keep relevance order).
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum SortOrder {
    UpdatedDesc,
    UpdatedAsc,
    CreatedDesc,
    CreatedAsc,
    TitleAsc,
    TitleDesc,
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub meta: NoteMeta,
    pub title_norm: String,
    pub body_norm: String,
    pub body: String,
}

#[derive(Debug, Default, Clone)]
pub struct Index {
    pub entries: Vec<Entry>,
    pub built_at_ms: i64,
}

/// NFKC + lowercase. Fullwidth/halfwidth and case differences collapse.
pub fn normalize(s: &str) -> String {
    s.nfkc().collect::<String>().to_lowercase()
}

impl Index {
    pub fn build(vault: &Vault) -> Result<Self, NoteError> {
        let mut entries = Vec::new();
        for meta in vault.list()? {
            let body = vault.read(&meta.id)?;
            entries.push(Entry {
                title_norm: normalize(&meta.title),
                body_norm: normalize(&body),
                body,
                meta,
            });
        }
        Ok(Index {
            entries,
            built_at_ms: crate::vault::now_ms(),
        })
    }

    /// Take creation times from Git.
    ///
    /// Git wins even when the filesystem reported a birth time, so both devices sort
    /// the same way (Android has no birth time at all, macOS does). Notes that Git has
    /// never seen keep whatever the filesystem said.
    pub fn apply_created_times(&mut self, times: &[(String, i64)]) -> usize {
        let mut updated = 0;
        for (id, ms) in times {
            if let Some(entry) = self.entries.iter_mut().find(|e| &e.meta.id == id) {
                if entry.meta.created_ms != *ms {
                    entry.meta.created_ms = *ms;
                    updated += 1;
                }
            }
        }
        updated
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// All terms must match (AND). An empty query returns every note
    /// (newest first) so the app can present a browsable list.
    pub fn search(&self, query: &str, tags: &[String], limit: usize) -> Vec<Hit> {
        let q = normalize(query.trim());
        let terms: Vec<&str> = q.split_whitespace().filter(|t| !t.is_empty()).collect();
        let want_tags: Vec<String> = tags.iter().map(|t| normalize(t.trim_start_matches('#'))).collect();

        let mut hits: Vec<Hit> = Vec::new();

        for e in &self.entries {
            if !want_tags.is_empty() {
                let have: Vec<String> = e.meta.tags.iter().map(|t| normalize(t)).collect();
                if !want_tags.iter().all(|w| have.iter().any(|h| h == w)) {
                    continue;
                }
            }

            if terms.is_empty() {
                hits.push(Hit {
                    id: e.meta.id.clone(),
                    title: e.meta.title.clone(),
                    snippet: first_line(&e.body),
                    score: 0,
                    tags: e.meta.tags.clone(),
                    mtime_ms: e.meta.mtime_ms,
                    created_ms: e.meta.created_ms,
                });
                continue;
            }

            let mut score = 0i32;
            let mut all = true;
            for t in &terms {
                let in_title = e.title_norm.contains(t);
                let body_count = e.body_norm.matches(t).count();
                if !in_title && body_count == 0 {
                    all = false;
                    break;
                }
                if in_title {
                    score += 100;
                    if e.title_norm == *t {
                        score += 500;
                    }
                }
                if body_count > 0 {
                    score += 10 + (body_count.min(10) as i32);
                }
            }
            if !all {
                continue;
            }

            let snippet = make_snippet(&e.body_norm, &e.body, &terms);
            hits.push(Hit {
                id: e.meta.id.clone(),
                title: e.meta.title.clone(),
                snippet,
                score,
                tags: e.meta.tags.clone(),
                mtime_ms: e.meta.mtime_ms,
                created_ms: e.meta.created_ms,
            });
        }

        hits.sort_by(|a, b| b.score.cmp(&a.score).then(b.mtime_ms.cmp(&a.mtime_ms)));
        if limit > 0 {
            hits.truncate(limit);
        }
        hits
    }

    /// All notes in the requested order, as list rows (snippet included, score 0).
    pub fn list_rows(&self, order: SortOrder) -> Vec<Hit> {
        let mut out: Vec<Hit> = self
            .entries
            .iter()
            .map(|e| Hit {
                id: e.meta.id.clone(),
                title: e.meta.title.clone(),
                // the list shows title / dates / tags only; a snippet costs a scan
                // of the body for every note on every reload
                snippet: String::new(),
                score: 0,
                tags: e.meta.tags.clone(),
                mtime_ms: e.meta.mtime_ms,
                created_ms: e.meta.created_ms,
            })
            .collect();

        match order {
            SortOrder::UpdatedDesc => {
                out.sort_by(|a, b| b.mtime_ms.cmp(&a.mtime_ms).then(a.title.cmp(&b.title)))
            }
            SortOrder::UpdatedAsc => {
                out.sort_by(|a, b| a.mtime_ms.cmp(&b.mtime_ms).then(a.title.cmp(&b.title)))
            }
            SortOrder::CreatedDesc => out.sort_by(|a, b| {
                b.created_ms
                    .cmp(&a.created_ms)
                    .then(b.mtime_ms.cmp(&a.mtime_ms))
                    .then(a.title.cmp(&b.title))
            }),
            SortOrder::CreatedAsc => out.sort_by(|a, b| {
                a.created_ms
                    .cmp(&b.created_ms)
                    .then(a.mtime_ms.cmp(&b.mtime_ms))
                    .then(a.title.cmp(&b.title))
            }),
            SortOrder::TitleAsc => out.sort_by(|a, b| a.title.cmp(&b.title)),
            SortOrder::TitleDesc => out.sort_by(|a, b| b.title.cmp(&a.title)),
        }
        out
    }

    /// Tag cloud: every tag with its note count, most used first.
    pub fn tags(&self) -> Vec<TagCount> {
        let mut map: Vec<TagCount> = Vec::new();
        for e in &self.entries {
            for t in &e.meta.tags {
                match map.iter_mut().find(|c| &c.tag == t) {
                    Some(c) => c.count += 1,
                    None => map.push(TagCount {
                        tag: t.clone(),
                        count: 1,
                    }),
                }
            }
        }
        map.sort_by(|a, b| b.count.cmp(&a.count).then(a.tag.cmp(&b.tag)));
        map
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct TagCount {
    pub tag: String,
    pub count: u32,
}

fn first_line(body: &str) -> String {
    body.lines()
        .map(|l| l.trim())
        .find(|l| !l.is_empty() && !l.starts_with('#'))
        .unwrap_or("")
        .chars()
        .take(120)
        .collect()
}

/// Snippet around the first matching term. NFKC keeps character counts stable
/// in practice, so a char-index mapping is good enough here.
fn make_snippet(norm: &str, orig: &str, terms: &[&str]) -> String {
    let mut pos: Option<usize> = None;
    for t in terms {
        if let Some(byte) = norm.find(t) {
            let chars = norm[..byte].chars().count();
            pos = Some(pos.map_or(chars, |p| p.min(chars)));
        }
    }
    let Some(center) = pos else {
        return first_line(orig);
    };
    let chars: Vec<char> = orig.chars().collect();
    let start = center.saturating_sub(20);
    let end = (center + 40).min(chars.len());
    let mut s = String::new();
    if start > 0 {
        s.push('…');
    }
    s.extend(&chars[start..end]);
    if end < chars.len() {
        s.push('…');
    }
    s.replace('\n', " ")
}
