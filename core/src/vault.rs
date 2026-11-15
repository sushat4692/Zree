use crate::error::NoteError;
use crate::tags;
use chrono::Local;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const ASSETS_DIR: &str = "assets";
pub const TRASH_DIR: &str = ".trash";
const MAX_TITLE_CHARS: usize = 100;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NoteMeta {
    /// Vault-relative path with `/` separators, e.g. `foo.md`
    pub id: String,
    /// File stem, shown as the note title.
    pub title: String,
    /// Absolute path on disk.
    pub path: String,
    pub mtime_ms: i64,
    /// Creation time from the filesystem when the platform supports it (APFS does,
    /// Android's ext4/f2fs does not — the app fills those from Git).
    pub created_ms: i64,
    pub bytes: u64,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct Vault {
    root: PathBuf,
}

impl Vault {
    pub fn open(root: impl AsRef<Path>) -> Result<Self, NoteError> {
        let root = root.as_ref();
        if !root.is_dir() {
            return Err(NoteError::NotFound(root.display().to_string()));
        }
        let root = fs::canonicalize(root)?;
        Ok(Vault { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn root_string(&self) -> String {
        self.root.display().to_string()
    }

    /// Every `.md` file in the vault, newest first.
    pub fn list(&self) -> Result<Vec<NoteMeta>, NoteError> {
        let mut out = Vec::new();
        self.walk(&self.root.clone(), &mut out)?;
        out.sort_by(|a, b| b.mtime_ms.cmp(&a.mtime_ms).then(a.title.cmp(&b.title)));
        Ok(out)
    }

    fn walk(&self, dir: &Path, out: &mut Vec<NoteMeta>) -> Result<(), NoteError> {
        let entries = fs::read_dir(dir)?;
        for entry in entries {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().to_string();
            let path = entry.path();
            let ty = entry.file_type()?;

            if ty.is_dir() {
                // skip dot dirs (.git, .trash, .obsidian) and the attachment dir
                if name.starts_with('.') || name == ASSETS_DIR {
                    continue;
                }
                self.walk(&path, out)?;
            } else if ty.is_file() && name.to_lowercase().ends_with(".md") {
                out.push(self.meta_for(&path)?);
            }
        }
        Ok(())
    }

    fn meta_for(&self, path: &Path) -> Result<NoteMeta, NoteError> {
        let meta = fs::metadata(path)?;
        let body = fs::read_to_string(path).unwrap_or_default();
        let id = self.relative_id(path);
        Ok(NoteMeta {
            title: file_stem(path),
            path: path.display().to_string(),
            mtime_ms: meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
            created_ms: meta
                .created()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
            bytes: meta.len(),
            tags: tags::extract(&body),
            id,
        })
    }

    fn relative_id(&self, path: &Path) -> String {
        path.strip_prefix(&self.root)
            .unwrap_or(path)
            .components()
            .map(|c| c.as_os_str().to_string_lossy().to_string())
            .collect::<Vec<_>>()
            .join("/")
    }

    pub fn path_of(&self, id: &str) -> Result<PathBuf, NoteError> {
        let id = id.trim_start_matches('/');
        if id.is_empty() {
            return Err(NoteError::NotFound(id.to_string()));
        }
        let candidate = self.root.join(id);
        let normalized = normalize_components(&candidate);
        if !normalized.starts_with(&self.root) {
            return Err(NoteError::InvalidTitle(id.to_string()));
        }
        Ok(normalized)
    }

    pub fn read(&self, id: &str) -> Result<String, NoteError> {
        let path = self.path_of(id)?;
        if !path.is_file() {
            return Err(NoteError::NotFound(id.to_string()));
        }
        Ok(fs::read_to_string(&path)?)
    }

    pub fn exists(&self, id: &str) -> bool {
        self.path_of(id).map(|p| p.is_file()).unwrap_or(false)
    }

    /// Overwrite an existing note (creates it if the id is new).
    pub fn write(&self, id: &str, body: &str) -> Result<NoteMeta, NoteError> {
        let path = self.path_of(id)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, body)?;
        self.meta_for(&path)
    }

    /// Create a new note. `title = None` produces `Untitled <yymmdd-hhmm>`.
    /// Collisions get a numeric suffix instead of overwriting.
    pub fn create(&self, title: Option<&str>, body: &str) -> Result<NoteMeta, NoteError> {
        let base = match title {
            Some(t) => sanitize_title(t)?,
            None => format!("Untitled {}", Local::now().format("%y%m%d-%H%M")),
        };
        let mut candidate = format!("{base}.md");
        let mut n = 2;
        while self.path_of(&candidate)?.exists() {
            candidate = format!("{base} {n}.md");
            n += 1;
            if n > 999 {
                return Err(NoteError::AlreadyExists(base));
            }
        }
        self.write(&candidate, body)
    }

    pub fn rename(&self, id: &str, new_title: &str) -> Result<NoteMeta, NoteError> {
        let from = self.path_of(id)?;
        if !from.is_file() {
            return Err(NoteError::NotFound(id.to_string()));
        }
        let title = sanitize_title(new_title)?;
        let to = from.with_file_name(format!("{title}.md"));
        if to != from && to.exists() {
            return Err(NoteError::AlreadyExists(to.display().to_string()));
        }
        if to != from {
            fs::rename(&from, &to)?;
        }
        self.meta_for(&to)
    }

    /// Resolve a Markdown link href to a note id in this vault.
    ///
    /// Accepts relative paths, vault-absolute paths, percent-encoded or raw
    /// file names, with or without the `.md` extension. Anchors (`#h`) and
    /// queries are ignored. External links return None.
    pub fn resolve_link(&self, note_id: &str, href: &str) -> Option<String> {
        let href = href.trim();
        if href.is_empty() || href.starts_with('#') {
            return None;
        }
        let lower = href.to_ascii_lowercase();
        if lower.starts_with("http://")
            || lower.starts_with("https://")
            || lower.starts_with("mailto:")
            || lower.starts_with("zree:")
        {
            return None;
        }
        let path_part = href.split('#').next().unwrap_or("").split('?').next().unwrap_or("");
        let decoded = percent_decode(path_part);
        let decoded = decoded.trim();
        if decoded.is_empty() {
            return None;
        }

        let base = self.path_of(note_id).ok().and_then(|p| p.parent().map(|d| d.to_path_buf()))?;
        let joined = if let Some(abs) = decoded.strip_prefix('/') {
            self.root.join(abs)
        } else {
            base.join(decoded)
        };

        let mut candidates = vec![normalize_components(&joined)];
        if joined.extension().is_none() {
            let mut with_ext = joined.clone();
            with_ext.set_extension("md");
            candidates.push(normalize_components(&with_ext));
        }
        for candidate in candidates {
            if candidate.is_file() && candidate.starts_with(&self.root) {
                return Some(self.relative_id(&candidate));
            }
        }
        None
    }

    /// Move a note into `.trash/` instead of deleting it.
    pub fn trash(&self, id: &str) -> Result<String, NoteError> {
        let from = self.path_of(id)?;
        if !from.is_file() {
            return Err(NoteError::NotFound(id.to_string()));
        }
        let trash = self.root.join(TRASH_DIR);
        fs::create_dir_all(&trash)?;
        let stem = file_stem(&from);
        let mut candidate = trash.join(format!("{stem}.md"));
        let mut n = 2;
        while candidate.exists() {
            candidate = trash.join(format!("{stem} {n}.md"));
            n += 1;
        }
        fs::rename(&from, &candidate)?;
        Ok(self.relative_id(&candidate))
    }
}

/// Minimal percent-decoding (UTF-8 aware) so `%20` and `%E3%83%A1` work.
fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).ok();
            if let Some(byte) = hex.and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn file_stem(path: &Path) -> String {
    path.file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default()
}

fn normalize_components(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Strip characters that are illegal in file names; never returns empty.
pub fn sanitize_title(title: &str) -> Result<String, NoteError> {
    let cleaned: String = title
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '\0' | '\n' | '\r' | '\t' => '-',
            c => c,
        })
        .collect();
    let cleaned = cleaned.trim().trim_start_matches('.').trim_start().to_string();
    // collapse dot runs so `../..` cannot survive as a suspicious id
    let mut cleaned = cleaned;
    while cleaned.contains("..") {
        cleaned = cleaned.replace("..", ".");
    }
    let cleaned = cleaned.trim_end_matches('.').trim_end().to_string();
    let cleaned: String = cleaned.chars().take(MAX_TITLE_CHARS).collect();
    let cleaned = cleaned.trim().to_string();
    if cleaned.is_empty() || cleaned.chars().all(|c| c == '.' || c == '-') {
        return Err(NoteError::InvalidTitle(title.to_string()));
    }
    Ok(cleaned)
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
