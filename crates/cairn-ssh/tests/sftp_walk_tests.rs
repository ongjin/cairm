use cairn_ssh::{WalkMatch, WalkOptions};

#[test]
fn walk_options_default_values() {
    let opts = WalkOptions::default();
    assert_eq!(opts.max_depth, 10);
    assert_eq!(opts.cap, 10_000);
    assert!(!opts.include_hidden);
}

#[test]
fn walk_match_fields_are_accessible() {
    let m = WalkMatch {
        path: "/a/b".into(),
        name: "b".into(),
        size: 42,
        is_directory: false,
        mtime: Some(1_700_000_000),
    };

    assert_eq!(m.name, "b");
}
