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

    /// Tag candidates for the given prefix (no `#`), e.g. "お客" -> "お客様打合せ".
    pub fn suggest_tags(&self, prefix: String, limit: u32) -> Vec<String> {
        self.current_index().suggest_tags(&prefix, limit as usize)
    }

    /// Note candidates for the given prefix (no `[`), newest first.
    pub fn suggest_notes(&self, prefix: String, limit: u32) -> Vec<crate::complete::NoteSuggestion> {
        self.current_index().suggest_notes(&prefix, limit as usize)
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

pub use crate::git::SyncReport;

/// Marker continuation when Return is pressed at the end of `line`.
#[uniffi::export]
pub fn list_action(line: String) -> crate::complete::ListAction {
    crate::complete::list_action(&line)
}

/// Apply (or toggle off) a block style on the current line.
#[uniffi::export]
pub fn format_block(line: String, kind: crate::complete::BlockKind) -> String {
    crate::complete::format_block(&line, kind)
}

/// Flip a task checkbox, converting a plain line into an unchecked task.
#[uniffi::export]
pub fn toggle_task(line: String) -> String {
    crate::complete::toggle_task(&line)
}

/// Tab (indent) / Shift-Tab (outdent) on a list line.
#[uniffi::export]
pub fn indent_line(line: String, outdent: bool) -> Option<String> {
    crate::complete::indent_list_line(&line, outdent)
}

/// Whether the text before the caret sits in something completable.
#[uniffi::export]
pub fn completion_context(before_cursor: String) -> Option<crate::complete::CompletionContext> {
    crate::complete::completion_context(&before_cursor)
}

/// Point libgit2's TLS backend at a PEM bundle.
///
/// macOS uses SecureTransport and ignores this; Android links OpenSSL, which has
/// no default trust store, so the app must supply one before cloning/fetching.
#[uniffi::export]
pub fn set_git_ca_bundle(path: String) -> Result<(), NoteError> {
    #[cfg(target_os = "android")]
    {
        // OpenSSL is built with no-stdio on Android, so libgit2 cannot load a CA
        // file. Parse the bundle and register each certificate in memory using
        // libgit2's internal OpenSSL hook.
        return android_ca::install(&path);
    }

    #[cfg(not(target_os = "android"))]
    {
        // SAFETY: libgit2 copies the path into its global options.
        unsafe { git2::opts::set_ssl_cert_file(&path) }.map_err(crate::git::git_err)
    }
}

#[cfg(target_os = "android")]
mod android_ca {
    use crate::error::NoteError;
    use std::ffi::{c_int, c_void, CString};

    extern "C" {
        // public libgit2 API; must run before touching the internal SSL context
        fn git_libgit2_init() -> c_int;
        // libgit2 internal (src/libgit2/streams/openssl.c): adds a certificate to
        // the SSL context's trust store. Not in the public API, but statically
        // linked into this library, so it resolves at link time.
        fn git_openssl__add_x509_cert(cert: *mut openssl_sys::X509) -> c_int;
    }

    /// OpenSSL is built with `no-stdio` for Android, so libgit2 cannot read a CA
    /// file. Parse the bundle in memory instead and register every certificate.
    pub fn install(path: &str) -> Result<(), NoteError> {
        // libgit2 creates its OpenSSL context during git_libgit2_init(); without
        // this the internal cert hook dereferences a null context.
        unsafe { git_libgit2_init() };

        let pem = std::fs::read(path).map_err(NoteError::from)?;
        let bio = unsafe {
            openssl_sys::BIO_new_mem_buf(pem.as_ptr() as *const c_void, pem.len() as c_int)
        };
        if bio.is_null() {
            return Err(NoteError::Git("CAバンドルを読めません".into()));
        }

        // keep the file path alive for error messages only
        let _ = CString::new(path).ok();

        let mut added = 0usize;
        loop {
            let cert = unsafe {
                openssl_sys::PEM_read_bio_X509(
                    bio,
                    std::ptr::null_mut(),
                    None,
                    std::ptr::null_mut(),
                )
            };
            if cert.is_null() {
                break;
            }
            let rc = unsafe { git_openssl__add_x509_cert(cert) };
            // libgit2's store took its own reference
            unsafe { openssl_sys::X509_free(cert) };
            if rc < 0 {
                unsafe { openssl_sys::BIO_free_all(bio) };
                return Err(NoteError::Git(format!(
                    "libgit2 rejected certificate #{added}"
                )));
            }
            added += 1;
        }
        unsafe { openssl_sys::BIO_free_all(bio) };

        if added == 0 {
            return Err(NoteError::Git("CAバンドルに証明書がありません".into()));
        }
        Ok(())
    }
}

/// True when the folder is a Git working copy.
#[uniffi::export]
pub fn is_git_repo(root: String) -> bool {
    crate::git::Git::is_repo(&root)
}

#[derive(uniffi::Object)]
pub struct GitRepo {
    inner: Mutex<crate::git::Git>,
}

#[uniffi::export]
impl GitRepo {
    #[uniffi::constructor]
    pub fn open(root: String, username: Option<String>, token: Option<String>) -> Result<Arc<Self>, NoteError> {
        let auth = crate::git::GitAuth { username, token };
        let git = crate::git::Git::open(&root, auth)?;
        Ok(Arc::new(GitRepo { inner: Mutex::new(git) }))
    }

    /// Open the repository in `root`, initialising one if there is none.
    #[uniffi::constructor]
    pub fn ensure(root: String) -> Result<Arc<Self>, NoteError> {
        let git = if crate::git::Git::is_repo(&root) {
            crate::git::Git::open(&root, crate::git::GitAuth::default())?
        } else {
            crate::git::Git::init(&root)?
        };
        Ok(Arc::new(GitRepo { inner: Mutex::new(git) }))
    }

    /// Clone `url` into `path` and return a handle.
    #[uniffi::constructor]
    pub fn clone(url: String, path: String, username: Option<String>, token: Option<String>) -> Result<Arc<Self>, NoteError> {
        let auth = crate::git::GitAuth { username, token };
        crate::git::Git::clone_into(&url, std::path::Path::new(&path), &auth)?;
        let git = crate::git::Git::open(&path, auth)?;
        Ok(Arc::new(GitRepo { inner: Mutex::new(git) }))
    }

    pub fn set_auth(&self, username: Option<String>, token: Option<String>) {
        let mut guard = self.inner.lock().unwrap();
        guard.set_auth(crate::git::GitAuth { username, token });
    }

    pub fn status(&self) -> Result<crate::git::GitStatus, NoteError> {
        self.inner.lock().unwrap().status()
    }

    pub fn remote_url(&self) -> String {
        self.inner.lock().unwrap().remote_url()
    }

    pub fn set_remote(&self, url: String) -> Result<(), NoteError> {
        self.inner.lock().unwrap().set_remote(&url)
    }

    pub fn log(&self, limit: u32) -> Result<Vec<crate::git::CommitInfo>, NoteError> {
        self.inner.lock().unwrap().log(limit)
    }

    pub fn commit_all(&self, message: String) -> Result<Option<String>, NoteError> {
        self.inner.lock().unwrap().commit_all(&message)
    }

    pub fn fetch(&self) -> Result<(), NoteError> {
        self.inner.lock().unwrap().fetch()
    }

    pub fn pull(&self) -> Result<crate::git::PullOutcome, NoteError> {
        self.inner.lock().unwrap().pull()
    }

    pub fn push(&self) -> Result<(), NoteError> {
        self.inner.lock().unwrap().push()
    }

    pub fn conflicts(&self) -> Result<Vec<String>, NoteError> {
        self.inner.lock().unwrap().conflicts()
    }

    pub fn resolve(&self, path: String, choice: crate::git::ConflictChoice) -> Result<(), NoteError> {
        self.inner.lock().unwrap().resolve(&path, choice)
    }

    pub fn commit_merge(&self, message: String) -> Result<(), NoteError> {
        self.inner.lock().unwrap().commit_merge(&message)
    }

    /// commit → pull → push. Conflicts stop the push and are returned.
    pub fn sync(&self, message: String) -> Result<SyncReport, NoteError> {
        self.inner.lock().unwrap().sync(&message)
    }
}
