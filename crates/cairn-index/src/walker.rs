use crate::store::{FileRow, FileKind, IndexStore};
use std::path::Path;
use walkdir::WalkDir;
use std::os::unix::fs::MetadataExt;

pub fn walk_into(root: &Path, store: &IndexStore) -> Result<usize, crate::IndexError> {
    let git_snap = cairn_git::snapshot(root);
    let git_status_for = |rel: &str| -> Option<u8> {
        let snap = git_snap.as_ref()?;
        let pb = std::path::PathBuf::from(rel);
        if snap.modified.contains(&pb)  { Some(b'M') }
        else if snap.added.contains(&pb)    { Some(b'A') }
        else if snap.deleted.contains(&pb)  { Some(b'D') }
        else if snap.untracked.contains(&pb){ Some(b'U') }
        else { None }
    };

    let mut count = 0;
    for entry in WalkDir::new(root).follow_links(false).into_iter().filter_entry(|e| {
        e.file_name().to_string_lossy() != ".git"
    }) {
        let entry = match entry { Ok(e) => e, Err(_) => continue };
        if entry.depth() == 0 { continue; }

        let rel = match entry.path().strip_prefix(root) {
            Ok(r) => r.to_string_lossy().into_owned(),
            Err(_) => continue,
        };
        let ft = entry.file_type();
        let kind = if ft.is_dir() { FileKind::Directory }
                   else if ft.is_symlink() { FileKind::Symlink }
                   else { FileKind::Regular };
        let md = match entry.metadata() { Ok(m) => m, Err(_) => continue };
        let row = FileRow {
            size: md.len(),
            mtime_unix: md.mtime(),
            kind,
            git_status: git_status_for(&rel),
            symbol_count: 0,
        };
        store.put_file(&rel, &row)?;
        count += 1;
        if matches!(kind, FileKind::Regular) {
            let syms = crate::symbols::extract_from_file(entry.path());
            if !syms.is_empty() {
                store.put_symbols(&rel, &syms).ok();
            }
        }
    }
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn walk_populates_store_with_regular_files() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("a.txt"), "aaa").unwrap();
        fs::write(tmp.path().join("b.swift"), "bb").unwrap();
        fs::create_dir(tmp.path().join("sub")).unwrap();
        fs::write(tmp.path().join("sub/c.md"), "c").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        let count = walk_into(tmp.path(), &store).unwrap();
        assert_eq!(count, 4); // 2 files + 1 dir + 1 file

        let all = store.list_all().unwrap();
        assert!(all.iter().any(|(p, _)| p == "a.txt"));
        assert!(all.iter().any(|(p, r)| p == "sub" && matches!(r.kind, FileKind::Directory)));
        assert!(all.iter().any(|(p, _)| p == "sub/c.md"));
    }

    #[test]
    fn walk_skips_dotgit() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir(tmp.path().join(".git")).unwrap();
        fs::write(tmp.path().join(".git/HEAD"), "ref").unwrap();
        fs::write(tmp.path().join("x.txt"), "x").unwrap();

        let db_tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&db_tmp.path().join("i.redb")).unwrap();
        walk_into(tmp.path(), &store).unwrap();

        let all = store.list_all().unwrap();
        assert!(all.iter().all(|(p, _)| !p.starts_with(".git")));
        assert!(all.iter().any(|(p, _)| p == "x.txt"));
    }
}
