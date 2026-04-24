use std::path::Path;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use cairn_ssh::{
    ConnectSpec, HostKeyResolver, KnownResult, PassphraseResolver, PasswordResolver, SftpHandle,
    SshPool, TofuDecision, WalkMatch, WalkOptions,
};

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

#[tokio::test]
async fn walk_finds_matches_up_to_cap() {
    let Some(host) = std::env::var("CAIRN_IT_SSH_HOST").ok() else {
        return;
    };
    let handle = open_test_handle(host).await;
    let found = Mutex::new(Vec::new());
    let cancel = Arc::new(AtomicBool::new(false));

    handle
        .walk(
            "/etc",
            WalkOptions {
                pattern: "conf".into(),
                cap: 10,
                ..Default::default()
            },
            cancel,
            |m| found.lock().unwrap().push(m),
        )
        .await
        .unwrap();

    let found = found.into_inner().unwrap();
    assert!(!found.is_empty());
    assert!(found.iter().all(|m| m.name.to_lowercase().contains("conf")));
    assert!(found.len() <= 10);
}

async fn open_test_handle(host_alias: String) -> SftpHandle {
    let pool = Arc::new(SshPool::new());
    let key = pool
        .connect(
            &ConnectSpec {
                host_alias,
                user_override: std::env::var("CAIRN_IT_SSH_USER").ok(),
                port_override: std::env::var("CAIRN_IT_SSH_PORT")
                    .ok()
                    .and_then(|p| p.parse().ok()),
                identity_file_override: std::env::var("CAIRN_IT_SSH_IDENTITY").ok().map(Into::into),
                proxy_command_override: None,
                password_override: std::env::var("CAIRN_IT_SSH_PASSWORD").ok(),
            },
            Arc::new(NoPassphrase),
            Arc::new(EnvPassword),
            Arc::new(AcceptHostKey),
        )
        .await
        .unwrap();

    SftpHandle::open(pool, key).await.unwrap()
}

struct NoPassphrase;

#[async_trait]
impl PassphraseResolver for NoPassphrase {
    async fn resolve(&self, _key_path: &Path) -> Option<String> {
        None
    }
}

struct EnvPassword;

#[async_trait]
impl PasswordResolver for EnvPassword {
    async fn resolve(&self, _host: &str, _user: &str) -> Option<String> {
        std::env::var("CAIRN_IT_SSH_PASSWORD").ok()
    }
}

struct AcceptHostKey;

#[async_trait]
impl HostKeyResolver for AcceptHostKey {
    async fn resolve(
        &self,
        _host: &str,
        _port: u16,
        _offered_algo: &str,
        _offered_blob: &[u8],
        _known: KnownResult,
    ) -> TofuDecision {
        TofuDecision::Accept
    }
}
