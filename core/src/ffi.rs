//! FFI surface consumed by the native apps (Swift on macOS, Kotlin on Android).
//!
//! Everything below is `uniffi::export`ed; the pure-Rust API in the rest of the
//! crate stays usable from tests and tools.

use crate::error::NoteError;
use crate::markdown::{self, Block, Inline};
use crate::search::{Hit, Index, TagCount};
use crate::vault::{NoteMeta, Vault};
use std::sync::{Arc, Mutex};

#[derive(uniffi::Object)]
pub struct ZreeSession {
    vault: Vault,
    index: Mutex<Index>,
    dirty: Mutex<bool>,
}

#[uniffi::export]
impl ZreeSession {
    /// Open a vault folder. Fails if the folder does not exist.
    #[uniffi::constructor]
    pub fn open(root: String) -> Result<Arc<Self>, NoteError> {
        let vault = Vault::open(&root)?;
        let index = Index::build(&vault)?;
        Ok(Arc::new(ZreeSession {
            vault,
            index: Mutex::new(index),
            dirty: Mutex::new(false),
        }))
    }

    pub fn root(&self) -> String {
        self.vault.root_string()
    }

    pub fn list(&self) -> Result<Vec<NoteMeta>, NoteError> {
        self.vault.list()
    }

    pub fn read(&self, id: String) -> Result<String, NoteError> {
        self.vault.read(&id)
    }

    /// Overwrite a note. Rejected when the file changed on disk since `seen_mtime_ms`.
    pub fn write(
        &self,
        id: String,
        body: String,
        seen_mtime_ms: i64,
    ) -> Result<NoteMeta, NoteError> {
        let path = self.vault.path_of(&id)?;
        if path.is_file() && seen_mtime_ms > 0 {
            let current = std::fs::metadata(&path)
                .and_then(|m| m.modified())
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            if current != seen_mtime_ms {
                return Err(NoteError::Conflict(format!(
                    "外部で更新されています: {id} (disk={current} mine={seen_mtime_ms})"
                )));
            }
        }
        let meta = self.vault.write(&id, &body)?;
        self.invalidate();
        Ok(meta)
    }

    pub fn create(&self, title: Option<String>, body: String) -> Result<NoteMeta, NoteError> {
        let meta = self.vault.create(title.as_deref(), &body)?;
        self.invalidate();
        Ok(meta)
    }

    pub fn rename(&self, id: String, title: String) -> Result<NoteMeta, NoteError> {
        let meta = self.vault.rename(&id, &title)?;
        self.invalidate();
        Ok(meta)
    }

    pub fn trash(&self, id: String) -> Result<String, NoteError> {
        let moved = self.vault.trash(&id)?;
        self.invalidate();
        Ok(moved)
    }

    pub fn search(&self, query: String, tags: Vec<String>, limit: u32) -> Vec<Hit> {
        let index = self.current_index();
        index.search(&query, &tags, limit as usize)
    }

    pub fn tags(&self) -> Vec<TagCount> {
        self.current_index().tags()
    }

    /// Markdown token stream for a note on disk.
    pub fn blocks(&self, id: String) -> Result<Vec<Block>, NoteError> {
        Ok(markdown::parse_blocks(&self.vault.read(&id)?))
    }

    /// Markdown token stream for live editor text (preview pane).
    pub fn blocks_of(&self, text: String) -> Vec<Block> {
        markdown::parse_blocks(&text)
    }

    pub fn inline(&self, text: String) -> Vec<Inline> {
        markdown::parse_inline(&text)
    }

    /// Image sources referenced by a note, for the native image loader.
    pub fn image_sources(&self, id: String) -> Result<Vec<String>, NoteError> {
        Ok(markdown::image_sources(&self.vault.read(&id)?))
    }

    /// Absolute path of a vault-relative resource (images etc.).
    pub fn resolve_asset(&self, id: String, src: String) -> Result<String, NoteError> {
        let note_dir = self
            .vault
            .path_of(&id)?
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| self.vault.root().to_path_buf());
        let candidate = note_dir.join(&src);
        if candidate.is_file() {
            return Ok(candidate.display().to_string());
        }
        let at_root = self.vault.root().join(&src);
        if at_root.is_file() {
            return Ok(at_root.display().to_string());
        }
        Err(NoteError::NotFound(src))
    }

    /// Resolve a Markdown link to a note id in this vault (None if external/missing).
    pub fn resolve_link(&self, id: String, href: String) -> Option<String> {
        self.vault.resolve_link(&id, &href)
    }

    /// Force a reindex (after a git pull, or when files changed outside the app).
    pub fn reindex(&self) -> Result<(), NoteError> {
        let rebuilt = Index::build(&self.vault)?;
        *self.index.lock().unwrap() = rebuilt;
        *self.dirty.lock().unwrap() = false;
        Ok(())
    }
}

impl ZreeSession {
    fn invalidate(&self) {
        *self.dirty.lock().unwrap() = true;
    }

    fn current_index(&self) -> std::sync::MutexGuard<'_, Index> {
        let mut guard = self.index.lock().unwrap();
        let dirty = *self.dirty.lock().unwrap();
        if dirty {
            if let Ok(rebuilt) = Index::build(&self.vault) {
                *guard = rebuilt;
                *self.dirty.lock().unwrap() = false;
            }
        }
        guard
    }
}
