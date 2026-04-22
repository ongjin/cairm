use redb::ReadableTable;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

const TABLE_FILES: redb::TableDefinition<&str, &[u8]> = redb::TableDefinition::new("files");

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileRow {
    pub size: u64,
    pub mtime_unix: i64,
    pub kind: FileKind,
    pub git_status: Option<GitStatusByte>,
    pub symbol_count: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum FileKind { Regular, Directory, Symlink }

/// Single-byte git status for compact storage.
/// M=modified, A=added, D=deleted, U=untracked, R=renamed.
pub type GitStatusByte = u8;

pub struct IndexStore {
    db: redb::Database,
}

impl IndexStore {
    pub fn open(db_path: &Path) -> Result<Self, IndexError> {
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let db = redb::Database::create(db_path).map_err(|e| IndexError::Db(e.into()))?;
        let tx = db.begin_write()?;
        {
            let _ = tx.open_table(TABLE_FILES)?;
        }
        tx.commit()?;
        Ok(Self { db })
    }

    pub fn put_file(&self, rel: &str, row: &FileRow) -> Result<(), IndexError> {
        let bytes = bincode::serialize(row)?;
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_FILES)?;
            t.insert(rel, bytes.as_slice())?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn get_file(&self, rel: &str) -> Result<Option<FileRow>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_FILES)?;
        match t.get(rel)? {
            Some(bytes) => Ok(Some(bincode::deserialize(bytes.value())?)),
            None => Ok(None),
        }
    }

    pub fn delete_file(&self, rel: &str) -> Result<(), IndexError> {
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_FILES)?;
            t.remove(rel)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn list_all(&self) -> Result<Vec<(String, FileRow)>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_FILES)?;
        let mut out = Vec::new();
        for entry in t.iter()? {
            let (k, v) = entry?;
            let row: FileRow = bincode::deserialize(v.value())?;
            out.push((k.value().to_string(), row));
        }
        Ok(out)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    #[error("redb: {0}")] Db(#[from] redb::Error),
    #[error("redb transaction: {0}")] Tx(#[from] redb::TransactionError),
    #[error("redb storage: {0}")] Storage(#[from] redb::StorageError),
    #[error("redb table: {0}")] Table(#[from] redb::TableError),
    #[error("redb commit: {0}")] Commit(#[from] redb::CommitError),
    #[error("bincode: {0}")] Codec(#[from] bincode::Error),
}

/// Compute cache path under user's cache dir.
pub fn cache_path_for(root: &Path) -> PathBuf {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(root.to_string_lossy().as_bytes());
    let hash = hex::encode(hasher.finalize());
    let base = dirs::cache_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("Cairn").join("index").join(format!("{hash}.redb"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample() -> FileRow {
        FileRow { size: 42, mtime_unix: 1_700_000_000, kind: FileKind::Regular, git_status: None, symbol_count: 0 }
    }

    #[test]
    fn put_get_roundtrip() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("foo/bar.txt", &sample()).unwrap();
        assert_eq!(store.get_file("foo/bar.txt").unwrap(), Some(sample()));
    }

    #[test]
    fn delete_removes_row() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("a.txt", &sample()).unwrap();
        store.delete_file("a.txt").unwrap();
        assert!(store.get_file("a.txt").unwrap().is_none());
    }

    #[test]
    fn list_all_returns_all() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("x.redb")).unwrap();
        store.put_file("a.txt", &sample()).unwrap();
        store.put_file("b.txt", &sample()).unwrap();
        let rows = store.list_all().unwrap();
        assert_eq!(rows.len(), 2);
    }
}
