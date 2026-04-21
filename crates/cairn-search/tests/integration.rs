use cairn_search::{next_batch, start, status, SearchMode, SearchOptions, SearchStatus};
use std::fs;
use tempfile::tempdir;

fn collect_all(h: cairn_search::SearchHandle) -> Vec<String> {
    let mut names = Vec::new();
    while let Some(batch) = next_batch(h) {
        for e in batch {
            names.push(e.name.clone());
        }
    }
    names
}

#[test]
fn smoke_empty_root() {
    let tmp = tempdir().unwrap();
    let h = start(
        tmp.path(),
        SearchOptions {
            query: "x".into(),
            mode: SearchMode::Folder,
            ..Default::default()
        },
    );
    assert!(collect_all(h).is_empty());
    assert_eq!(status(h), SearchStatus::Done);
}

#[test]
fn folder_mode_matches_only_direct_children() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join("readme.txt"), b"").unwrap();
    fs::write(tmp.path().join("README.md"), b"").unwrap();
    fs::create_dir(tmp.path().join("sub")).unwrap();
    fs::write(tmp.path().join("sub/readme_inner.txt"), b"").unwrap();

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "readme".into(),
            mode: SearchMode::Folder,
            ..Default::default()
        },
    );
    let names = collect_all(h);
    assert_eq!(names.len(), 2, "got {:?}", names);
    assert!(names.iter().any(|n| n == "readme.txt"));
    assert!(names.iter().any(|n| n == "README.md"));
}

#[test]
fn case_insensitive_match() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join("FooBar.txt"), b"").unwrap();

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "FOOBAR".into(),
            mode: SearchMode::Folder,
            ..Default::default()
        },
    );
    let names = collect_all(h);
    assert_eq!(names, vec!["FooBar.txt"]);
}
