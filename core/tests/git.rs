use std::fs;
use std::path::Path;
use zree_core::git::{ConflictChoice, Git, GitAuth, PullOutcome};

fn write(path: &Path, body: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, body).unwrap();
}

struct Sandbox {
    _dir: tempfile::TempDir,
    remote: String,
}

impl Sandbox {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let remote_path = dir.path().join("remote.git");
        git2::Repository::init_bare(&remote_path).unwrap();
        Sandbox {
            remote: remote_path.display().to_string(),
            _dir: dir,
        }
    }

    fn path(&self, name: &str) -> std::path::PathBuf {
        self._dir.path().join(name)
    }

    /// A fresh vault+repo wired to the shared bare remote.
    fn vault(&self, name: &str) -> (std::path::PathBuf, Git) {
        let dir = self.path(name);
        fs::create_dir_all(&dir).unwrap();
        let git = Git::init(&dir).unwrap();
        git.set_remote(&self.remote).unwrap();
        (dir, git)
    }

    fn clone(&self, name: &str) -> (std::path::PathBuf, Git) {
        let dir = self.path(name);
        Git::clone_into(&self.remote, &dir, &GitAuth::default()).unwrap();
        let git = Git::open(&dir, GitAuth::default()).unwrap();
        (dir, git)
    }
}

#[test]
fn commit_push_then_pull_fast_forward() {
    let sandbox = Sandbox::new();
    let (a_dir, a) = sandbox.vault("a");
    write(&a_dir.join("note.md"), "# A\nこんにちは\n");

    let status = a.status().unwrap();
    assert_eq!(status.changed, 1, "untracked file should be counted");
    assert_eq!(status.remote_url, sandbox.remote);

    assert!(a.commit_all("最初のコミット").unwrap().is_some());
    assert_eq!(a.status().unwrap().changed, 0);
    assert!(a.commit_all("空コミット").unwrap().is_none(), "no changes, no commit");

    a.push().unwrap();
    let log = a.log(5).unwrap();
    assert_eq!(log.len(), 1);
    assert_eq!(log[0].summary, "最初のコミット");

    // second machine clones, edits, pushes
    let (b_dir, b) = sandbox.clone("b");
    assert_eq!(fs::read_to_string(b_dir.join("note.md")).unwrap(), "# A\nこんにちは\n");
    write(&b_dir.join("note.md"), "# A\nこんにちは\n追記\n");
    write(&b_dir.join("新しい.md"), "新規\n");
    b.commit_all("Bの変更").unwrap();
    b.push().unwrap();

    // first machine pulls: fast-forward
    let outcome = a.pull().unwrap();
    assert_eq!(outcome, PullOutcome::FastForwarded { commits: 1 });
    assert!(fs::read_to_string(a_dir.join("note.md")).unwrap().contains("追記"));
    assert!(a_dir.join("新しい.md").is_file());
    assert_eq!(a.pull().unwrap(), PullOutcome::UpToDate);
}

#[test]
fn divergent_edits_produce_conflicts_that_can_be_resolved() {
    let sandbox = Sandbox::new();
    let (a_dir, a) = sandbox.vault("a");
    write(&a_dir.join("共有.md"), "一行目\n");
    a.commit_all("init").unwrap();
    a.push().unwrap();

    let (b_dir, b) = sandbox.clone("b");
    let (c_dir, _c) = sandbox.clone("c");

    // B pushes a change
    write(&b_dir.join("共有.md"), "一行目 (B)\n");
    b.commit_all("Bの変更").unwrap();
    b.push().unwrap();

    // C edits the same lines locally, without pushing
    write(&a_dir.join("共有.md"), "一行目 (A)\n");
    a.commit_all("Aの変更").unwrap();

    let outcome = a.pull().unwrap();
    let paths = match outcome {
        PullOutcome::Conflicts { paths } => paths,
        other => panic!("expected conflicts, got {other:?}"),
    };
    assert_eq!(paths, vec!["共有.md".to_string()]);
    assert!(a.status().unwrap().merging);
    assert_eq!(a.conflicts().unwrap(), vec!["共有.md".to_string()]);

    // take theirs, finish the merge, and push the result
    a.resolve("共有.md", ConflictChoice::Theirs).unwrap();
    a.commit_merge("衝突を解決").unwrap();
    assert!(a.conflicts().unwrap().is_empty());
    assert!(!a.status().unwrap().merging);
    assert_eq!(fs::read_to_string(a_dir.join("共有.md")).unwrap(), "一行目 (B)\n");

    a.push().unwrap();
    b.pull().unwrap();
    assert_eq!(fs::read_to_string(b_dir.join("共有.md")).unwrap(), "一行目 (B)\n");
}

#[test]
fn resolves_both_sides_when_asked() {
    let sandbox = Sandbox::new();
    let (a_dir, a) = sandbox.vault("a");
    write(&a_dir.join("x.md"), "base\n");
    a.commit_all("init").unwrap();
    a.push().unwrap();

    let (b_dir, b) = sandbox.clone("b");
    write(&b_dir.join("x.md"), "theirs\n");
    b.commit_all("b").unwrap();
    b.push().unwrap();

    write(&a_dir.join("x.md"), "mine\n");
    a.commit_all("a").unwrap();
    assert!(matches!(a.pull().unwrap(), PullOutcome::Conflicts { .. }));

    a.resolve("x.md", ConflictChoice::Both).unwrap();
    a.commit_merge("both").unwrap();
    let body = fs::read_to_string(a_dir.join("x.md")).unwrap();
    assert!(body.contains("mine") && body.contains("theirs"), "got {body}");
}

#[test]
fn reports_remotes_and_handles_missing_repo() {
    let dir = tempfile::tempdir().unwrap();
    assert!(!Git::is_repo(dir.path()));

    let git = Git::init(dir.path()).unwrap();
    assert!(Git::is_repo(dir.path()));
    assert_eq!(git.status().unwrap().remote_url, "");
    // no remote configured -> a clear error, not a panic
    assert!(git.fetch().is_err());
    assert!(git.push().is_err());
}

#[test]
fn ffi_clone_is_what_the_app_calls() {
    let sandbox = Sandbox::new();
    let (a_dir, a) = sandbox.vault("a");
    write(&a_dir.join("n.md"), "ノート\n");
    a.commit_all("init").unwrap();
    a.push().unwrap();

    let dest = sandbox.path("cloned");
    let dest_str = dest.display().to_string();
    assert!(!zree_core::ffi::is_git_repo(dest_str.clone()));

    let repo = zree_core::ffi::GitRepo::clone(
        sandbox.remote.clone(),
        dest_str.clone(),
        None,
        None,
    )
    .unwrap();

    assert!(zree_core::ffi::is_git_repo(dest_str));
    assert!(dest.join("n.md").is_file());
    let status = repo.status().unwrap();
    assert_eq!(status.changed, 0, "fresh clone should be clean");
    assert_eq!(status.remote_url, sandbox.remote);
}
