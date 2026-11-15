//! Shared note core.
//!
//! Native UIs (SwiftUI on macOS, Compose on Android) call into this crate.
//! It owns everything that must behave identically on both platforms:
//! vault IO, Japanese search, tag extraction, Markdown tokenising and Git.

uniffi::setup_scaffolding!();

pub mod complete;
pub mod error;
pub mod ffi;
pub mod git;
pub mod markdown;
pub mod search;
pub mod tags;
pub mod vault;

pub use complete::{completion_context, list_action, CompletionContext, CompletionKind, ListAction, NoteSuggestion};
pub use error::NoteError;
pub use markdown::{parse_blocks, parse_inline, Block, Inline};
pub use search::{Hit, Index, SortOrder, TagCount};
pub use vault::{NoteMeta, Vault};

/// Convenience facade: a vault plus its in-memory search index.
pub struct Session {
    pub vault: Vault,
    pub index: Index,
}

impl Session {
    pub fn open(root: impl AsRef<std::path::Path>) -> Result<Self, NoteError> {
        let vault = Vault::open(root)?;
        let index = Index::build(&vault)?;
        Ok(Session { vault, index })
    }

    /// Rebuild only the search index (cheap at this vault size).
    pub fn reindex(&mut self) -> Result<(), NoteError> {
        self.index = Index::build(&self.vault)?;
        Ok(())
    }
}
