use cairn_search::{
    cancel, next_batch, start, status, SearchHandle, SearchMode, SearchOptions, SearchStatus,
};
use std::fs;
use std::thread::sleep;
use std::time::Duration;
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
    assert_eq!(names.len(), 2, "got {names:?}");
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

#[test]
fn subtree_mode_recursive() {
    let tmp = tempdir().unwrap();
    fs::create_dir_all(tmp.path().join("a/b")).unwrap();
    fs::write(tmp.path().join("a/hello.txt"), b"").unwrap();
    fs::write(tmp.path().join("a/b/hello.md"), b"").unwrap();
    fs::write(tmp.path().join("unrelated.txt"), b"").unwrap();

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "hello".into(),
            mode: SearchMode::Subtree,
            ..Default::default()
        },
    );
    let names = collect_all(h);
    assert_eq!(names.len(), 2, "got {names:?}");
    assert!(names.iter().any(|n| n == "hello.txt"));
    assert!(names.iter().any(|n| n == "hello.md"));
}

#[test]
fn gitignore_respected_when_hidden_off() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join(".gitignore"), b"build/\n").unwrap();
    fs::create_dir(tmp.path().join("build")).unwrap();
    fs::write(tmp.path().join("build/secret.txt"), b"").unwrap();
    fs::write(tmp.path().join("keep.txt"), b"").unwrap();

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "".into(),
            mode: SearchMode::Subtree,
            show_hidden: false,
            ..Default::default()
        },
    );
    let names = collect_all(h);
    assert!(!names.contains(&"secret.txt".to_string()), "got {names:?}");
    assert!(names.contains(&"keep.txt".to_string()));
}

#[test]
fn subtree_hidden_files_off_skips_dotfiles() {
    let tmp = tempdir().unwrap();
    fs::write(tmp.path().join(".hidden.txt"), b"").unwrap();
    fs::write(tmp.path().join("visible.txt"), b"").unwrap();

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "".into(),
            mode: SearchMode::Subtree,
            show_hidden: false,
            ..Default::default()
        },
    );
    let names = collect_all(h);
    assert!(!names.contains(&".hidden.txt".to_string()));
    assert!(names.contains(&"visible.txt".to_string()));
}

#[test]
fn cancel_mid_walk() {
    let tmp = tempdir().unwrap();
    // Make a wide tree so the walker doesn't finish instantly.
    for i in 0..200 {
        fs::write(tmp.path().join(format!("f{i}.txt")), b"").unwrap();
    }

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "".into(),
            mode: SearchMode::Subtree,
            batch_size: 16, // force multiple batches
            ..Default::default()
        },
    );
    // Let the walker produce one batch, then cancel.
    sleep(Duration::from_millis(20));
    cancel(h);

    // Drain whatever is still coming. Must terminate (no hang).
    let mut total = 0;
    while let Some(b) = next_batch(h) {
        total += b.len();
        if total > 200 {
            break; // safety net
        }
    }
    assert!(total <= 200);
}

#[test]
fn cap_enforcement() {
    let tmp = tempdir().unwrap();
    for i in 0..20 {
        fs::write(tmp.path().join(format!("hit{i}.txt")), b"").unwrap();
    }

    let h = start(
        tmp.path(),
        SearchOptions {
            query: "hit".into(),
            mode: SearchMode::Folder,
            result_cap: 10,
            ..Default::default()
        },
    );

    // Pull batches until exhausted; observe status BEFORE the channel's
    // Disconnected signal evicts the session from the registry (after which
    // `status` would return Done unconditionally).
    let mut names = Vec::new();
    let mut observed_capped = false;
    while let Some(batch) = next_batch(h) {
        for e in batch {
            names.push(e.name.clone());
        }
        if status(h) == SearchStatus::Capped {
            observed_capped = true;
        }
    }
    assert_eq!(names.len(), 10, "got {names:?}");
    assert!(observed_capped, "status never transitioned to Capped");
}

#[test]
fn invalid_handle_safe() {
    let bad = SearchHandle(999_999_999);
    assert!(next_batch(bad).is_none());
    assert_eq!(status(bad), SearchStatus::Done);
    cancel(bad); // must not panic
}

#[test]
fn concurrent_sessions_independent() {
    let tmp1 = tempdir().unwrap();
    fs::write(tmp1.path().join("alpha.txt"), b"").unwrap();
    let tmp2 = tempdir().unwrap();
    fs::write(tmp2.path().join("beta.txt"), b"").unwrap();

    let h1 = start(
        tmp1.path(),
        SearchOptions {
            query: "alpha".into(),
            mode: SearchMode::Folder,
            ..Default::default()
        },
    );
    let h2 = start(
        tmp2.path(),
        SearchOptions {
            query: "beta".into(),
            mode: SearchMode::Folder,
            ..Default::default()
        },
    );

    let names1 = collect_all(h1);
    let names2 = collect_all(h2);
    assert_eq!(names1, vec!["alpha.txt"]);
    assert_eq!(names2, vec!["beta.txt"]);
}
