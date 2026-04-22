use crate::store::IndexStore;
use nucleo_matcher::{
    pattern::{CaseMatching, Normalization, Pattern},
    Config, Matcher, Utf32Str,
};

#[derive(Debug, Clone)]
pub struct FileHit {
    pub path_rel: String,
    pub score: u32,
    /// Byte offsets in path_rel that matched, used by UI for highlighting.
    pub matches: Vec<u32>,
    /// 0 = Regular, 1 = Directory, 2 = Symlink. Mirrors `FileKind`'s discriminant
    /// order so the FFI layer doesn't need a translation table.
    pub kind: u8,
}

fn kind_byte(k: crate::store::FileKind) -> u8 {
    match k {
        crate::store::FileKind::Regular => 0,
        crate::store::FileKind::Directory => 1,
        crate::store::FileKind::Symlink => 2,
    }
}

pub fn query(
    store: &IndexStore,
    needle: &str,
    limit: usize,
) -> Result<Vec<FileHit>, crate::IndexError> {
    let rows = store.list_all()?;

    if needle.is_empty() {
        return Ok(rows
            .into_iter()
            .take(limit)
            .map(|(p, row)| FileHit {
                path_rel: p,
                score: 0,
                matches: Vec::new(),
                kind: kind_byte(row.kind),
            })
            .collect());
    }

    let mut matcher = Matcher::new(Config::DEFAULT);
    let pattern = Pattern::parse(needle, CaseMatching::Smart, Normalization::Smart);

    let mut scored: Vec<FileHit> = rows
        .iter()
        .filter_map(|(path, row)| {
            let mut buf = Vec::new();
            let hay = Utf32Str::new(path, &mut buf);
            let mut indices: Vec<u32> = Vec::new();
            let score = pattern.indices(hay, &mut matcher, &mut indices)?;
            Some(FileHit {
                path_rel: path.clone(),
                score,
                matches: indices,
                kind: kind_byte(row.kind),
            })
        })
        .collect();

    scored.sort_by(|a, b| b.score.cmp(&a.score));
    scored.truncate(limit);
    Ok(scored)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::{FileKind, FileRow, IndexStore};
    use tempfile::TempDir;

    fn sample(store: &IndexStore, paths: &[&str]) {
        for p in paths {
            let row = FileRow {
                size: 0,
                mtime_unix: 0,
                kind: FileKind::Regular,
                git_status: None,
                symbol_count: 0,
            };
            store.put_file(p, &row).unwrap();
        }
    }

    #[test]
    fn empty_needle_returns_all_up_to_limit() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("i.redb")).unwrap();
        sample(&store, &["a.txt", "b.txt", "c.txt"]);
        let hits = query(&store, "", 2).unwrap();
        assert_eq!(hits.len(), 2);
    }

    #[test]
    fn fuzzy_ranks_substring_higher() {
        let tmp = TempDir::new().unwrap();
        let store = IndexStore::open(&tmp.path().join("i.redb")).unwrap();
        sample(&store, &["foo.txt", "barfoo.txt", "unrelated.txt"]);
        let hits = query(&store, "foo", 10).unwrap();
        assert_eq!(hits[0].path_rel, "foo.txt");
        assert!(hits.iter().any(|h| h.path_rel == "barfoo.txt"));
        assert!(hits.iter().all(|h| h.path_rel != "unrelated.txt"));
    }
}
