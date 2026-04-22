use redb::ReadableTable;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    RwLock,
};

const TABLE_FILES: redb::TableDefinition<&str, &[u8]> = redb::TableDefinition::new("files");
const TABLE_SYMBOLS: redb::TableDefinition<(&str, u32), &[u8]> =
    redb::TableDefinition::new("symbols");

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FileRow {
    pub size: u64,
    pub mtime_unix: i64,
    pub kind: FileKind,
    pub git_status: Option<GitStatusByte>,
    pub symbol_count: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum FileKind {
    Regular,
    Directory,
    Symlink,
}

/// Single-byte git status for compact storage.
/// M=modified, A=added, D=deleted, U=untracked, R=renamed.
pub type GitStatusByte = u8;

pub struct IndexStore {
    db: redb::Database,
    // In-memory cache of the TABLE_FILES contents. Invalidated by a
    // generation counter bumped on every file mutation (put_file /
    // delete_file). TABLE_SYMBOLS writes do NOT invalidate — symbols
    // live in their own table.
    files_cache: RwLock<Option<CachedFiles>>,
    files_gen: AtomicU64,
}

struct CachedFiles {
    gen: u64,
    files: Vec<(String, FileRow)>,
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
            let _ = tx.open_table(TABLE_SYMBOLS)?;
        }
        tx.commit()?;
        Ok(Self {
            db,
            files_cache: RwLock::new(None),
            files_gen: AtomicU64::new(0),
        })
    }

    pub fn put_file(&self, rel: &str, row: &FileRow) -> Result<(), IndexError> {
        self.files_gen.fetch_add(1, Ordering::AcqRel);
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
        self.files_gen.fetch_add(1, Ordering::AcqRel);
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_FILES)?;
            t.remove(rel)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn list_all(&self) -> Result<Vec<(String, FileRow)>, IndexError> {
        let current_gen = self.files_gen.load(Ordering::Acquire);

        // Fast path: cache hit.
        if let Ok(guard) = self.files_cache.read() {
            if let Some(c) = guard.as_ref() {
                if c.gen == current_gen {
                    return Ok(c.files.clone());
                }
            }
        }

        // Slow path: rebuild from redb.
        let files = self.list_all_from_db()?;
        if let Ok(mut slot) = self.files_cache.write() {
            *slot = Some(CachedFiles {
                gen: current_gen,
                files: files.clone(),
            });
        }
        Ok(files)
    }

    fn list_all_from_db(&self) -> Result<Vec<(String, FileRow)>, IndexError> {
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

    pub fn put_symbols(
        &self,
        rel: &str,
        syms: &[crate::symbols::SymbolRow],
    ) -> Result<(), IndexError> {
        let tx = self.db.begin_write()?;
        {
            let mut t = tx.open_table(TABLE_SYMBOLS)?;
            // Clear existing for this file.
            let keys: Vec<(String, u32)> = {
                let read = t.iter()?;
                read.filter_map(|e| e.ok().map(|(k, _)| (k.value().0.to_string(), k.value().1)))
                    .collect()
            };
            for (p, idx) in keys.iter().filter(|(p, _)| p == rel) {
                t.remove((p.as_str(), *idx))?;
            }
            for (i, s) in syms.iter().enumerate() {
                let bytes = bincode::serialize(s)?;
                t.insert((rel, i as u32), bytes.as_slice())?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn query_symbols(
        &self,
        needle: &str,
        limit: usize,
    ) -> Result<Vec<(String, crate::symbols::SymbolRow)>, IndexError> {
        let tx = self.db.begin_read()?;
        let t = tx.open_table(TABLE_SYMBOLS)?;
        let mut out = Vec::new();
        let needle_lc = needle.to_lowercase();
        for entry in t.iter()? {
            let (k, v) = entry?;
            let (rel, _idx) = k.value();
            let row: crate::symbols::SymbolRow = bincode::deserialize(v.value())?;
            if needle.is_empty() || row.name.to_lowercase().contains(&needle_lc) {
                out.push((rel.to_string(), row));
            }
            if out.len() >= limit {
                break;
            }
        }
        Ok(out)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    #[error("redb: {0}")]
    Db(#[from] redb::Error),
    #[error("redb transaction: {0}")]
    Tx(#[from] redb::TransactionError),
    #[error("redb storage: {0}")]
    Storage(#[from] redb::StorageError),
    #[error("redb table: {0}")]
    Table(#[from] redb::TableError),
    #[error("redb commit: {0}")]
    Commit(#[from] redb::CommitError),
    #[error("bincode: {0}")]
    Codec(#[from] bincode::Error),
}

/// Compute cache path under user's cache dir.
pub fn cache_path_for(root: &Path) -> PathBuf {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(root.to_string_lossy().as_bytes());
    let hash = hex::encode(hasher.finalize());
    let base = dirs::cache_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("Cairn")
        .join("index")
        .join(format!("{hash}.redb"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample() -> FileRow {
        FileRow {
            size: 42,
            mtime_unix: 1_700_000_000,
            kind: FileKind::Regular,
            git_status: None,
            symbol_count: 0,
        }
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

    #[test]
    fn list_all_cache_hits_on_repeated_calls_without_mutation() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("idx.redb")).unwrap();

        store.put_file("a.txt", &sample()).unwrap();
        store.put_file("b.txt", &sample()).unwrap();

        let first = store.list_all().unwrap();
        let second = store.list_all().unwrap();
        // Same content, cache must serve the second call.
        assert_eq!(first, second);
        assert_eq!(first.len(), 2);
    }

    #[test]
    fn list_all_cache_invalidates_on_put_and_delete() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("idx.redb")).unwrap();

        store.put_file("a.txt", &sample()).unwrap();

        let before_insert = store.list_all().unwrap();
        store.put_file("b.txt", &sample()).unwrap();
        let after_insert = store.list_all().unwrap();

        assert_eq!(before_insert.len(), 1);
        assert_eq!(after_insert.len(), 2);

        store.delete_file("a.txt").unwrap();
        let after_delete = store.list_all().unwrap();
        assert_eq!(after_delete.len(), 1);
        assert_eq!(after_delete[0].0, "b.txt");
    }
}
