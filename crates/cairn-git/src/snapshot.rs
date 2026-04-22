use std::path::{Path, PathBuf};

use git2::{Repository, StatusOptions};

/// Status for one file relative to a repository root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    Modified,
    Added,
    Deleted,
    Untracked,
    Renamed,
}

#[derive(Debug, Clone)]
pub struct GitSnapshot {
    pub branch: Option<String>,
    pub modified: Vec<PathBuf>,
    pub added: Vec<PathBuf>,
    pub deleted: Vec<PathBuf>,
    pub untracked: Vec<PathBuf>,
}

pub fn snapshot(root: &Path) -> Option<GitSnapshot> {
    let repo = Repository::discover(root).ok()?;

    let branch = match repo.head() {
        Ok(head) => head.shorthand().map(String::from),
        Err(_) => repo
            .find_reference("HEAD")
            .ok()
            .and_then(|r| r.symbolic_target().map(String::from))
            .and_then(|t| t.strip_prefix("refs/heads/").map(String::from)),
    };

    let mut opts = StatusOptions::new();
    opts.include_untracked(true).recurse_untracked_dirs(true);

    let mut modified = Vec::new();
    let mut added = Vec::new();
    let mut deleted = Vec::new();
    let mut untracked = Vec::new();

    let statuses = repo.statuses(Some(&mut opts)).ok()?;
    for s in statuses.iter() {
        let path = match s.path() {
            Some(p) => PathBuf::from(p),
            None => continue,
        };
        let flags = s.status();
        if flags.intersects(git2::Status::WT_MODIFIED | git2::Status::INDEX_MODIFIED) {
            modified.push(path);
        } else if flags.intersects(git2::Status::INDEX_NEW) {
            added.push(path);
        } else if flags.intersects(git2::Status::WT_DELETED | git2::Status::INDEX_DELETED) {
            deleted.push(path);
        } else if flags.contains(git2::Status::WT_NEW) {
            untracked.push(path);
        }
    }

    Some(GitSnapshot {
        branch,
        modified,
        added,
        deleted,
        untracked,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Command;
    use tempfile::TempDir;

    fn init_repo() -> TempDir {
        let tmp = TempDir::new().unwrap();
        Command::new("git")
            .args(["init", "-q", "-b", "main"])
            .current_dir(tmp.path())
            .status()
            .unwrap();
        Command::new("git")
            .args(["config", "user.email", "t@t"])
            .current_dir(tmp.path())
            .status()
            .unwrap();
        Command::new("git")
            .args(["config", "user.name", "t"])
            .current_dir(tmp.path())
            .status()
            .unwrap();
        tmp
    }

    #[test]
    fn not_a_repo_returns_none() {
        let tmp = TempDir::new().unwrap();
        assert!(snapshot(tmp.path()).is_none());
    }

    #[test]
    fn empty_repo_returns_branch_no_changes() {
        let tmp = init_repo();
        let snap = snapshot(tmp.path()).unwrap();
        assert_eq!(snap.branch.as_deref(), Some("main"));
        assert!(snap.modified.is_empty());
        assert!(snap.untracked.is_empty());
    }

    #[test]
    fn untracked_file_appears() {
        let tmp = init_repo();
        fs::write(tmp.path().join("hello.txt"), "hi").unwrap();
        let snap = snapshot(tmp.path()).unwrap();
        assert_eq!(snap.untracked.len(), 1);
        assert_eq!(snap.untracked[0], PathBuf::from("hello.txt"));
    }

    #[test]
    fn modified_file_appears() {
        let tmp = init_repo();
        fs::write(tmp.path().join("a.txt"), "orig").unwrap();
        Command::new("git")
            .args(["add", "a.txt"])
            .current_dir(tmp.path())
            .status()
            .unwrap();
        Command::new("git")
            .args(["commit", "-q", "-m", "init"])
            .current_dir(tmp.path())
            .status()
            .unwrap();
        fs::write(tmp.path().join("a.txt"), "changed").unwrap();
        let snap = snapshot(tmp.path()).unwrap();
        assert_eq!(snap.modified.len(), 1);
        assert_eq!(snap.modified[0], PathBuf::from("a.txt"));
    }
}
