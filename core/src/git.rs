//! Git sync (libgit2).
//!
//! The vault *is* the repository: notes are committed, pulled and pushed as
//! plain files. Conflicts are surfaced as data, never as a panic, so the UI can
//! ask the user what to do.

use crate::error::NoteError;
use git2::{CredentialType, Repository, RepositoryState, StatusOptions};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GitStatus {
    pub is_repo: bool,
    pub branch: String,
    pub upstream: String,
    pub ahead: u32,
    pub behind: u32,
    pub changed: u32,
    pub conflicts: Vec<String>,
    pub remote_url: String,
    pub merging: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CommitInfo {
    pub id: String,
    pub summary: String,
    pub author: String,
    pub time_ms: i64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum PullOutcome {
    UpToDate,
    FastForwarded { commits: u32 },
    MergedClean,
    Conflicts { paths: Vec<String> },
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ConflictChoice {
    Mine,
    Theirs,
    Both,
}

#[derive(Debug, Clone, Default)]
pub struct GitAuth {
    pub username: Option<String>,
    pub token: Option<String>,
}

pub struct Git {
    repo: Repository,
    root: PathBuf,
    auth: GitAuth,
}

impl Git {
    pub fn open(root: impl AsRef<Path>, auth: GitAuth) -> Result<Self, NoteError> {
        let root = root.as_ref().to_path_buf();
        let repo = Repository::open(&root).map_err(git_err)?;
        Ok(Git { repo, root, auth })
    }

    pub fn init(root: impl AsRef<Path>) -> Result<Self, NoteError> {
        let root = root.as_ref().to_path_buf();
        let repo = Repository::init(&root).map_err(git_err)?;
        Ok(Git {
            repo,
            root,
            auth: GitAuth::default(),
        })
    }

    pub fn set_auth(&mut self, auth: GitAuth) {
        self.auth = auth;
    }

    pub fn is_repo(root: impl AsRef<Path>) -> bool {
        Repository::open(root.as_ref()).is_ok()
    }

    // MARK: - status

    pub fn status(&self) -> Result<GitStatus, NoteError> {
        let branch = self.current_branch();
        let mut opts = StatusOptions::new();
        opts.include_untracked(true)
            .recurse_untracked_dirs(true)
            .exclude_submodules(true);

        let statuses = self.repo.statuses(Some(&mut opts)).map_err(git_err)?;
        let mut changed = 0u32;
        let mut conflicts = Vec::new();
        for entry in statuses.iter() {
            let s = entry.status();
            if s.is_conflicted() {
                if let Ok(p) = entry.path() {
                    conflicts.push(p.to_string());
                }
            } else if !s.is_ignored() {
                changed += 1;
            }
        }

        let (ahead, behind) = self.ahead_behind().unwrap_or((0, 0));
        let remote_url = self
            .repo
            .find_remote("origin")
            .ok()
            .and_then(|r| r.url().ok().map(|u| u.to_string()))
            .unwrap_or_default();

        let merging = matches!(
            self.repo.state(),
            RepositoryState::Merge | RepositoryState::Revert | RepositoryState::CherryPick
        );

        Ok(GitStatus {
            is_repo: true,
            branch,
            upstream: self.upstream_name(),
            ahead,
            behind,
            changed,
            conflicts,
            remote_url,
            merging,
        })
    }

    fn current_branch(&self) -> String {
        self.repo
            .head()
            .ok()
            .and_then(|h| h.shorthand().ok().map(|s| s.to_string()))
            .unwrap_or_else(|| "main".to_string())
    }

    fn upstream_name(&self) -> String {
        match self.repo.head() {
            Ok(head) => head
                .shorthand()
                .ok()
                .map(|s| format!("origin/{s}"))
                .unwrap_or_default(),
            Err(_) => String::new(),
        }
    }

    fn ahead_behind(&self) -> Result<(u32, u32), NoteError> {
        let head = match self.repo.head() {
            Ok(h) => h,
            Err(_) => return Ok((0, 0)),
        };
        let local = match head.peel_to_commit() {
            Ok(c) => c,
            Err(_) => return Ok((0, 0)),
        };
        let branch = self.current_branch();
        let remote_ref = format!("refs/remotes/origin/{branch}");
        let upstream = match self.repo.find_reference(&remote_ref) {
            Ok(r) => r,
            Err(_) => return Ok((0, 0)),
        };
        let theirs = match upstream.peel_to_commit() {
            Ok(c) => c,
            Err(_) => return Ok((0, 0)),
        };
        let (ahead, behind) = self
            .repo
            .graph_ahead_behind(local.id(), theirs.id())
            .map_err(git_err)?;
        Ok((ahead as u32, behind as u32))
    }

    pub fn log(&self, limit: u32) -> Result<Vec<CommitInfo>, NoteError> {
        let mut out = Vec::new();
        let mut revwalk = self.repo.revwalk().map_err(git_err)?;
        if revwalk.push_head().is_err() {
            return Ok(out);
        }
        for oid in revwalk.take(limit as usize) {
            let oid = oid.map_err(git_err)?;
            if let Ok(commit) = self.repo.find_commit(oid) {
                out.push(CommitInfo {
                    id: oid.to_string(),
                    summary: commit.summary().ok().flatten().unwrap_or("").to_string(),
                    author: commit
                        .author()
                        .name()
                        .ok()
                        .map(|n| n.to_string())
                        .unwrap_or_default(),
                    time_ms: commit.time().seconds() * 1000,
                });
            }
        }
        Ok(out)
    }

    // MARK: - remote & credentials

    pub fn remote_url(&self) -> String {
        self.repo
            .find_remote("origin")
            .ok()
            .and_then(|r| r.url().ok().map(|u| u.to_string()))
            .unwrap_or_default()
    }

    pub fn set_remote(&self, url: &str) -> Result<(), NoteError> {
        match self.repo.find_remote("origin") {
            Ok(_) => self.repo.remote_set_url("origin", url).map_err(git_err),
            Err(_) => {
                self.repo.remote("origin", url).map_err(git_err)?;
                Ok(())
            }
        }
    }

    /// Clone `url` into an existing empty directory (used for first-time setup).
    pub fn clone_into(url: &str, path: &Path, auth: &GitAuth) -> Result<(), NoteError> {
        let mut callbacks = git2::RemoteCallbacks::new();
        let a = auth.clone();
        callbacks.credentials(move |_u, user, allowed| cred(&a, user, allowed));
        let mut fo = git2::FetchOptions::new();
        fo.remote_callbacks(callbacks);
        let mut builder = git2::build::RepoBuilder::new();
        builder.fetch_options(fo);
        builder.clone(url, path).map_err(git_err)?;
        Ok(())
    }

    fn credentials(&self) -> git2::RemoteCallbacks<'_> {
        let mut callbacks = git2::RemoteCallbacks::new();
        let auth = self.auth.clone();
        callbacks.credentials(move |_url, user, allowed| cred(&auth, user, allowed));
        callbacks
    }

    // MARK: - commit / fetch / pull / push

    pub fn commit_all(&self, message: &str) -> Result<Option<String>, NoteError> {
        let mut index = self.repo.index().map_err(git_err)?;
        index
            .add_all(["."], git2::IndexAddOption::DEFAULT, None)
            .map_err(git_err)?;
        index.update_all(["."], None).map_err(git_err)?;
        index.write().map_err(git_err)?;

        let tree_oid = index.write_tree().map_err(git_err)?;

        // nothing staged -> nothing to commit
        let head_tree = self
            .repo
            .head()
            .ok()
            .and_then(|h| h.peel_to_tree().ok())
            .map(|t| t.id());
        if Some(tree_oid) == head_tree {
            return Ok(None);
        }

        let tree = self.repo.find_tree(tree_oid).map_err(git_err)?;
        let sig = self.signature()?;
        let parents: Vec<git2::Commit> = match self.repo.head().ok().and_then(|h| h.peel_to_commit().ok()) {
            Some(c) => vec![c],
            None => Vec::new(),
        };
        let parent_refs: Vec<&git2::Commit> = parents.iter().collect();
        let oid = self
            .repo
            .commit(Some("HEAD"), &sig, &sig, message, &tree, &parent_refs)
            .map_err(git_err)?;
        Ok(Some(oid.to_string()))
    }

    pub fn fetch(&self) -> Result<(), NoteError> {
        let mut remote = self
            .repo
            .find_remote("origin")
            .map_err(|_| NoteError::Io("リモート origin が設定されていません".into()))?;
        let callbacks = self.credentials();
        let mut fo = git2::FetchOptions::new();
        fo.remote_callbacks(callbacks);
        remote
            .fetch(&["refs/heads/*:refs/remotes/origin/*"], Some(&mut fo), None)
            .map_err(git_err)?;
        Ok(())
    }

    pub fn pull(&self) -> Result<PullOutcome, NoteError> {
        self.fetch()?;
        let branch = self.current_branch();
        let remote_ref = format!("refs/remotes/origin/{branch}");
        let upstream = self
            .repo
            .find_reference(&remote_ref)
            .map_err(|_| NoteError::Io(format!("リモートブランチ {branch} が見つかりません")))?;
        let target = upstream.peel_to_commit().map_err(git_err)?;

        let head_commit = self.repo.head().ok().and_then(|h| h.peel_to_commit().ok());

        let (ahead, behind) = match &head_commit {
            Some(local) => self
                .repo
                .graph_ahead_behind(local.id(), target.id())
                .map_err(git_err)?,
            None => (0, 1),
        };

        if behind == 0 {
            return Ok(PullOutcome::UpToDate);
        }

        if ahead == 0 {
            // fast-forward
            self.checkout_commit(&target)?;
            let reference = self.repo.find_reference(&format!("refs/heads/{branch}"));
            match reference {
                Ok(mut r) => {
                    r.set_target(target.id(), "zree: fast-forward")
                        .map_err(git_err)?;
                }
                Err(_) => {
                    self.repo
                        .reference(&format!("refs/heads/{branch}"), target.id(), true, "zree")
                        .map_err(git_err)?;
                }
            }
            self.repo.set_head(&format!("refs/heads/{branch}")).map_err(git_err)?;
            self.checkout_commit(&target)?;
            return Ok(PullOutcome::FastForwarded { commits: behind as u32 });
        }

        // real merge
        let annotated = self
            .repo
            .reference_to_annotated_commit(&upstream)
            .map_err(git_err)?;
        let mut checkout = git2::build::CheckoutBuilder::new();
        checkout.safe();
        self.repo
            .merge(&[&annotated], None, Some(&mut checkout))
            .map_err(git_err)?;
        let index = self.repo.index().map_err(git_err)?;
        if index.has_conflicts() {
            let paths = conflict_paths(&index);
            return Ok(PullOutcome::Conflicts { paths });
        }
        self.finish_merge(&target)?;
        Ok(PullOutcome::MergedClean)
    }

    fn checkout_commit(&self, commit: &git2::Commit<'_>) -> Result<(), NoteError> {
        let mut opts = git2::build::CheckoutBuilder::new();
        opts.force().remove_untracked(false);
        self.repo.checkout_tree(commit.as_object(), Some(&mut opts)).map_err(git_err)?;
        Ok(())
    }

    fn finish_merge(&self, theirs: &git2::Commit<'_>) -> Result<(), NoteError> {
        let mut index = self.repo.index().map_err(git_err)?;
        let tree_oid = index.write_tree().map_err(git_err)?;
        let tree = self.repo.find_tree(tree_oid).map_err(git_err)?;
        let sig = self.signature()?;
        let ours = self.repo.head().and_then(|h| h.peel_to_commit()).map_err(git_err)?;
        let msg = format!("zree: merge origin/{}", self.current_branch());
        self.repo
            .commit(Some("HEAD"), &sig, &sig, &msg, &tree, &[&ours, theirs])
            .map_err(git_err)?;
        self.repo.cleanup_state().map_err(git_err)?;
        Ok(())
    }

    pub fn push(&self) -> Result<(), NoteError> {
        let branch = self.current_branch();
        let mut remote = self
            .repo
            .find_remote("origin")
            .map_err(|_| NoteError::Io("リモート origin が設定されていません".into()))?;
        let callbacks = self.credentials();
        let mut po = git2::PushOptions::new();
        po.remote_callbacks(callbacks);
        let refspec = format!("refs/heads/{branch}:refs/heads/{branch}");
        remote.push(&[refspec.as_str()], Some(&mut po)).map_err(git_err)?;
        Ok(())
    }

    // MARK: - conflicts

    pub fn conflicts(&self) -> Result<Vec<String>, NoteError> {
        let index = self.repo.index().map_err(git_err)?;
        Ok(conflict_paths(&index))
    }

    /// Resolve one conflicted path and stage the result.
    pub fn resolve(&self, path: &str, choice: ConflictChoice) -> Result<(), NoteError> {
        let mut index = self.repo.index().map_err(git_err)?;

        let (ours_oid, theirs_oid) = {
            let mut conflicts = index.conflicts().map_err(git_err)?;
            let mut found: Option<(Option<git2::Oid>, Option<git2::Oid>)> = None;
            while let Some(item) = conflicts.next() {
                let c = item.map_err(git_err)?;
                let p = c
                    .our
                    .as_ref()
                    .or(c.their.as_ref())
                    .or(c.ancestor.as_ref())
                    .and_then(|e| std::str::from_utf8(&e.path).ok())
                    .map(|s| s.to_string());
                if p.as_deref() == Some(path) {
                    found = Some((
                        c.our.as_ref().map(|e| e.id),
                        c.their.as_ref().map(|e| e.id),
                    ));
                    break;
                }
            }
            found.ok_or_else(|| NoteError::NotFound(path.to_string()))?
        };

        let body = match choice {
            ConflictChoice::Mine => read_blob(&self.repo, ours_oid),
            ConflictChoice::Theirs => read_blob(&self.repo, theirs_oid),
            ConflictChoice::Both => {
                let a = read_blob(&self.repo, ours_oid).unwrap_or_default();
                let b = read_blob(&self.repo, theirs_oid).unwrap_or_default();
                Some(format!("{a}\n{b}"))
            }
        }
        .unwrap_or_default();

        let target = self.root.join(path);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&target, body)?;

        index.remove_path(Path::new(path)).ok();
        index.add_path(Path::new(path)).map_err(git_err)?;
        index.write().map_err(git_err)?;
        Ok(())
    }

    /// Complete a merge once every conflict is resolved.
    pub fn commit_merge(&self, message: &str) -> Result<(), NoteError> {
        let branch = self.current_branch();
        let remote_ref = format!("refs/remotes/origin/{branch}");
        let upstream = self.repo.find_reference(&remote_ref).map_err(git_err)?;
        let theirs = upstream.peel_to_commit().map_err(git_err)?;

        let mut index = self.repo.index().map_err(git_err)?;
        if index.has_conflicts() {
            return Err(NoteError::Conflict("未解決の衝突が残っています".into()));
        }
        let tree_oid = index.write_tree().map_err(git_err)?;
        let tree = self.repo.find_tree(tree_oid).map_err(git_err)?;
        let sig = self.signature()?;
        let ours = self.repo.head().and_then(|h| h.peel_to_commit()).map_err(git_err)?;
        self.repo
            .commit(Some("HEAD"), &sig, &sig, message, &tree, &[&ours, &theirs])
            .map_err(git_err)?;
        self.repo.cleanup_state().map_err(git_err)?;
        Ok(())
    }

    fn signature(&self) -> Result<git2::Signature<'static>, NoteError> {
        self.repo
            .signature()
            .or_else(|_| git2::Signature::now("Zree", "zree@localhost"))
            .map_err(git_err)
    }
}

fn conflict_paths(index: &git2::Index) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(mut conflicts) = index.conflicts() {
        while let Some(Ok(c)) = conflicts.next() {
            let entry = c.our.as_ref().or(c.their.as_ref()).or(c.ancestor.as_ref());
            if let Some(e) = entry {
                if let Ok(p) = std::str::from_utf8(&e.path) {
                    out.push(p.to_string());
                }
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

fn read_blob(repo: &Repository, oid: Option<git2::Oid>) -> Option<String> {
    let oid = oid?;
    let blob = repo.find_blob(oid).ok()?;
    Some(String::from_utf8_lossy(blob.content()).to_string())
}

fn cred(auth: &GitAuth, user_from_url: Option<&str>, allowed: CredentialType) -> Result<git2::Cred, git2::Error> {
    let user = auth
        .username
        .clone()
        .or_else(|| user_from_url.map(|s| s.to_string()))
        .unwrap_or_else(|| "git".to_string());

    if allowed.contains(CredentialType::SSH_KEY) {
        return git2::Cred::ssh_key_from_agent(&user);
    }
    if allowed.contains(CredentialType::USER_PASS_PLAINTEXT) {
        if let Some(token) = &auth.token {
            return git2::Cred::userpass_plaintext(&user, token);
        }
    }
    if allowed.contains(CredentialType::DEFAULT) {
        return git2::Cred::default();
    }
    git2::Cred::default()
}

fn git_err(e: git2::Error) -> NoteError {
    NoteError::Git(e.message().to_string())
}
