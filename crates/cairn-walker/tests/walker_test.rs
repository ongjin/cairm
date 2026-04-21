use cairn_walker::{list_directory, FileKind, WalkerConfig};
use std::fs;
use std::io::Write;

fn mk_tempdir_with_fixtures() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    let root = dir.path();

    // Regular file
    let mut f = fs::File::create(root.join("README.md")).unwrap();
    writeln!(f, "hello").unwrap();

    // Hidden file
    fs::File::create(root.join(".secret")).unwrap();

    // Subdirectory (non-empty)
    fs::create_dir(root.join("src")).unwrap();
    fs::File::create(root.join("src").join("lib.rs")).unwrap();

    // A commonly-excluded dir
    fs::create_dir(root.join("node_modules")).unwrap();
    fs::File::create(root.join("node_modules").join("index.js")).unwrap();

    // macOS noise
    fs::File::create(root.join(".DS_Store")).unwrap();

    dir
}

#[test]
fn lists_direct_children_only() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();

    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    // Direct children of the tempdir: README.md and src/ (node_modules excluded,
    // .secret hidden-out, .DS_Store always excluded).
    assert!(
        names.contains(&"README.md"),
        "expected README.md, got {names:?}"
    );
    assert!(names.contains(&"src"), "expected src/, got {names:?}");
    assert!(
        !names.contains(&"node_modules"),
        "node_modules should be excluded"
    );
    assert!(!names.contains(&".secret"), ".secret should be hidden");
    assert!(
        !names.contains(&".DS_Store"),
        ".DS_Store should always be excluded"
    );
    // Must NOT descend into src/ — this is a single-level listing.
    assert!(
        !names.contains(&"lib.rs"),
        "lib.rs is a grandchild, not direct child"
    );
}

#[test]
fn show_hidden_includes_dotfiles() {
    let dir = mk_tempdir_with_fixtures();
    let cfg = WalkerConfig {
        show_hidden: true,
        ..Default::default()
    };
    let entries = list_directory(dir.path(), &cfg).unwrap();
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert!(
        names.contains(&".secret"),
        "dotfile should appear when show_hidden=true"
    );
    // But .DS_Store is ALWAYS excluded regardless of show_hidden.
    assert!(!names.contains(&".DS_Store"));
}

#[test]
fn directory_entries_have_zero_size_and_directory_kind() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();
    let src = entries
        .iter()
        .find(|e| e.name == "src")
        .expect("src must be listed");
    assert_eq!(src.kind, FileKind::Directory);
    assert_eq!(src.size, 0);
    assert_eq!(src.icon_kind, cairn_walker::IconKind::Folder);
}

#[test]
fn regular_file_has_extension_hint() {
    let dir = mk_tempdir_with_fixtures();
    let entries = list_directory(dir.path(), &WalkerConfig::default()).unwrap();
    let readme = entries.iter().find(|e| e.name == "README.md").unwrap();
    assert_eq!(readme.kind, FileKind::Regular);
    assert_eq!(
        readme.icon_kind,
        cairn_walker::IconKind::ExtensionHint("md".to_string())
    );
}

#[test]
fn returns_not_directory_for_file_path() {
    let dir = mk_tempdir_with_fixtures();
    let file = dir.path().join("README.md");
    let err = list_directory(&file, &WalkerConfig::default()).unwrap_err();
    matches!(err, cairn_walker::WalkerError::NotDirectory);
}

#[test]
fn returns_not_found_for_missing_path() {
    let err = list_directory(
        std::path::Path::new("/definitely/not/a/real/path/xyz"),
        &WalkerConfig::default(),
    )
    .unwrap_err();
    matches!(err, cairn_walker::WalkerError::NotFound);
}
