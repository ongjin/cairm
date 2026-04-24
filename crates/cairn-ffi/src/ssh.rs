use async_trait::async_trait;
use cairn_ssh::{self as ssh, config};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc::UnboundedReceiver;
use tokio::task::JoinHandle;

use ffi::{ConnKeyBridge, ConnectSpecBridge, FileStatBridge};

// NOTE: Vec<FileEntryBridge> cannot be returned directly through swift-bridge
// because `swift_repr = "struct"` types are not Vectorizable. We use an opaque
// SftpListingBridge wrapper with len()/entry(i) accessors — same idiom as
// FileListing and GitPathList in lib.rs / git.rs.
//
// String-owned types are used for path parameters (instead of &str) to avoid
// a swift-bridge codegen bug where `toRustStr` closures inside Result
// unwrapping generate non-throwing closures that the Swift compiler rejects.

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct ConnKeyBridge {
        user: String,
        hostname: String,
        port: u16,
        config_hash_hex: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct FileEntryBridge {
        name: String,
        is_dir: bool,
        size: u64,
        mtime: i64,
        mode: u32,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct FileStatBridge {
        size: u64,
        mtime: i64,
        mode: u32,
        is_dir: bool,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct WalkMatchBridge {
        path: String,
        name: String,
        size: i64,
        is_directory: bool,
        /// Zero means "mtime unavailable" on the Swift side.
        mtime: i64,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct ConnectSpecBridge {
        host_alias: String,
        user_override: Option<String>,
        port_override: Option<u16>,
        identity_file_override: Option<String>,
        proxy_command_override: Option<String>,
        /// Plain-text password for password-auth hosts. Empty string = unset.
        password_override: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct HostKeyOffer {
        algorithm: String,
        blob_base64: String,
        fingerprint: String,
    }

    extern "Swift" {
        type HostKeyCallback;
        #[swift_bridge(swift_name = "askHostKey")]
        fn ask_host_key(
            &self,
            host: String,
            port: u16,
            offer: HostKeyOffer,
            state: String,
        ) -> String;
    }

    extern "Swift" {
        type PassphraseCallback;
        #[swift_bridge(swift_name = "askPassphrase")]
        fn ask_passphrase(&self, key_path: String) -> Option<String>;
    }

    extern "Swift" {
        type PasswordCallback;
        #[swift_bridge(swift_name = "askPassword")]
        fn ask_password(&self, host: String, user: String) -> Option<String>;
    }

    extern "Rust" {
        type SshPoolBridge;
        type SftpHandleBridge;
        type CancelFlagBridge;
        /// Opaque listing returned by sftp_list — iterate with len()/entry(i).
        type SftpListingBridge;
        type SftpWalkSessionBridge;
        type SftpWalkBatchBridge;

        fn ssh_pool_new() -> SshPoolBridge;
        fn ssh_pool_list_configured_hosts() -> Vec<String>;
        fn ssh_pool_connect(
            pool: &SshPoolBridge,
            spec: ConnectSpecBridge,
            hostkey_cb: HostKeyCallback,
            passphrase_cb: PassphraseCallback,
            password_cb: PasswordCallback,
        ) -> Result<ConnKeyBridge, String>;
        fn ssh_pool_disconnect(pool: &SshPoolBridge, key: ConnKeyBridge);
        fn ssh_pool_close_all(pool: &SshPoolBridge);

        fn ssh_open_sftp(
            pool: &SshPoolBridge,
            key: ConnKeyBridge,
        ) -> Result<SftpHandleBridge, String>;

        // sftp_list returns an opaque SftpListingBridge to work around
        // the swift-bridge limitation that Vec<swift_repr="struct"> is unsupported.
        fn sftp_list(h: &SftpHandleBridge, path: String) -> Result<SftpListingBridge, String>;
        fn sftp_realpath(h: &SftpHandleBridge, path: String) -> Result<String, String>;
        fn sftp_stat(h: &SftpHandleBridge, path: String) -> Result<FileStatBridge, String>;
        fn sftp_mkdir(h: &SftpHandleBridge, path: String) -> Result<(), String>;
        fn sftp_rename(h: &SftpHandleBridge, from: String, to: String) -> Result<(), String>;
        fn sftp_unlink(h: &SftpHandleBridge, path: String) -> Result<(), String>;
        fn sftp_read_head(h: &SftpHandleBridge, path: String, max: u32) -> Result<Vec<u8>, String>;

        fn cancel_flag_new() -> CancelFlagBridge;
        fn cancel_flag_cancel(f: &CancelFlagBridge);

        fn sftp_download_sync(
            h: &SftpHandleBridge,
            remote: String,
            local: String,
            cancel: &CancelFlagBridge,
        ) -> Result<(), String>;
        fn sftp_upload_sync(
            h: &SftpHandleBridge,
            local: String,
            remote: String,
            cancel: &CancelFlagBridge,
        ) -> Result<(), String>;
        fn sftp_progress_poll(h: &SftpHandleBridge) -> u64;

        fn ssh_sftp_walk_start(
            h: &SftpHandleBridge,
            root: String,
            pattern: String,
            max_depth: u32,
            cap: u32,
            include_hidden: bool,
        ) -> SftpWalkSessionBridge;
        fn ssh_sftp_walk_drain(session: &SftpWalkSessionBridge, max: u32) -> SftpWalkBatchBridge;
        fn ssh_sftp_walk_cancel(session: &SftpWalkSessionBridge);
        fn ssh_sftp_walk_is_done(session: &SftpWalkSessionBridge) -> bool;

        // SftpListingBridge accessors — iterate the result of sftp_list.
        fn sftp_listing_len(listing: &SftpListingBridge) -> usize;
        fn sftp_listing_entry(listing: &SftpListingBridge, index: usize) -> FileEntryBridge;

        fn sftp_walk_batch_len(batch: &SftpWalkBatchBridge) -> usize;
        fn sftp_walk_batch_entry(batch: &SftpWalkBatchBridge, index: usize) -> WalkMatchBridge;
    }
}

// ---------------------------------------------------------------------------
// Bridge opaque types
// ---------------------------------------------------------------------------

pub struct SshPoolBridge {
    inner: Arc<ssh::SshPool>,
}

pub struct SftpHandleBridge {
    inner: ssh::SftpHandle,
    progress: Arc<AtomicU64>,
}

pub struct CancelFlagBridge {
    inner: ssh::CancelFlag,
}

pub struct SftpListingBridge {
    entries: Vec<ssh::RemoteEntry>,
}

pub struct SftpWalkSessionBridge {
    rx: Mutex<UnboundedReceiver<ssh::WalkMatch>>,
    cancel: Arc<AtomicBool>,
    join: Mutex<Option<JoinHandle<Result<(), String>>>>,
}

pub struct SftpWalkBatchBridge {
    matches: Vec<ssh::WalkMatch>,
}

impl Drop for SftpWalkSessionBridge {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::Relaxed);
        if let Ok(mut join) = self.join.lock() {
            if let Some(handle) = join.take() {
                handle.abort();
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Shared tokio runtime
// ---------------------------------------------------------------------------

fn runtime() -> &'static tokio::runtime::Runtime {
    use std::sync::OnceLock;
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .unwrap()
    })
}

// ---------------------------------------------------------------------------
// Swift-backed resolver adapters
// ---------------------------------------------------------------------------

struct SwiftHostKeyAdapter {
    cb: ffi::HostKeyCallback,
}

// Safety: the callback is invoked exclusively from within a single-threaded
// block_on call; the Swift side serialises access via DispatchSemaphore.
unsafe impl Send for SwiftHostKeyAdapter {}
unsafe impl Sync for SwiftHostKeyAdapter {}

#[async_trait]
impl ssh::HostKeyResolver for SwiftHostKeyAdapter {
    async fn resolve(
        &self,
        host: &str,
        port: u16,
        offered_algo: &str,
        offered_blob: &[u8],
        known: ssh::KnownResult,
    ) -> ssh::TofuDecision {
        use base64::prelude::*;
        let offer = ffi::HostKeyOffer {
            algorithm: offered_algo.to_string(),
            blob_base64: BASE64_STANDARD.encode(offered_blob),
            fingerprint: ssh::sha256_fingerprint(offered_blob),
        };
        let state = match known {
            ssh::KnownResult::Match => "match".to_string(),
            ssh::KnownResult::NotFound => "not_found".to_string(),
            ssh::KnownResult::Mismatch { .. } => "mismatch".to_string(),
        };
        let result = self.cb.ask_host_key(host.to_string(), port, offer, state);
        match result.as_str() {
            "accept" => ssh::TofuDecision::Accept,
            "accept_save" => ssh::TofuDecision::AcceptAndSave,
            _ => ssh::TofuDecision::Reject,
        }
    }
}

struct SwiftPassphraseAdapter {
    cb: ffi::PassphraseCallback,
}

// Safety: same as SwiftHostKeyAdapter — single-threaded block_on + Semaphore.
unsafe impl Send for SwiftPassphraseAdapter {}
unsafe impl Sync for SwiftPassphraseAdapter {}

#[async_trait]
impl ssh::PassphraseResolver for SwiftPassphraseAdapter {
    async fn resolve(&self, key_path: &std::path::Path) -> Option<String> {
        self.cb
            .ask_passphrase(key_path.to_string_lossy().into_owned())
    }
}

struct SwiftPasswordAdapter {
    cb: ffi::PasswordCallback,
}

// Safety: same as SwiftHostKeyAdapter — single-threaded block_on + Semaphore.
unsafe impl Send for SwiftPasswordAdapter {}
unsafe impl Sync for SwiftPasswordAdapter {}

#[async_trait]
impl ssh::PasswordResolver for SwiftPasswordAdapter {
    async fn resolve(&self, host: &str, user: &str) -> Option<String> {
        self.cb.ask_password(host.to_string(), user.to_string())
    }
}

// ---------------------------------------------------------------------------
// Free functions exposed to Swift
// ---------------------------------------------------------------------------

fn ssh_pool_new() -> SshPoolBridge {
    let pool = runtime().block_on(async { ssh::SshPool::new() });
    SshPoolBridge {
        inner: Arc::new(pool),
    }
}

fn ssh_pool_list_configured_hosts() -> Vec<String> {
    config::list_configured_hosts()
}

fn ssh_pool_connect(
    pool: &SshPoolBridge,
    spec: ConnectSpecBridge,
    hostkey_cb: ffi::HostKeyCallback,
    passphrase_cb: ffi::PassphraseCallback,
    password_cb: ffi::PasswordCallback,
) -> Result<ConnKeyBridge, String> {
    let password_override = if spec.password_override.is_empty() {
        None
    } else {
        Some(spec.password_override)
    };
    let spec = ssh::ConnectSpec {
        host_alias: spec.host_alias,
        user_override: spec.user_override,
        port_override: spec.port_override,
        identity_file_override: spec.identity_file_override.map(Into::into),
        proxy_command_override: spec.proxy_command_override,
        password_override,
    };
    let hk = Arc::new(SwiftHostKeyAdapter { cb: hostkey_cb });
    let pp = Arc::new(SwiftPassphraseAdapter { cb: passphrase_cb });
    let pw = Arc::new(SwiftPasswordAdapter { cb: password_cb });
    let key = runtime()
        .block_on(pool.inner.connect(&spec, pp, pw, hk))
        .map_err(|e| e.to_string())?;
    Ok(key_to_bridge(&key))
}

fn ssh_pool_disconnect(pool: &SshPoolBridge, key: ConnKeyBridge) {
    let k = bridge_to_key(key);
    runtime().block_on(pool.inner.disconnect(&k));
}

fn ssh_pool_close_all(pool: &SshPoolBridge) {
    runtime().block_on(pool.inner.close_all());
}

fn ssh_open_sftp(pool: &SshPoolBridge, key: ConnKeyBridge) -> Result<SftpHandleBridge, String> {
    let k = bridge_to_key(key);
    let sftp = runtime()
        .block_on(ssh::SftpHandle::open(pool.inner.clone(), k))
        .map_err(|e| e.to_string())?;
    Ok(SftpHandleBridge {
        inner: sftp,
        progress: Arc::new(AtomicU64::new(0)),
    })
}

fn sftp_list(h: &SftpHandleBridge, path: String) -> Result<SftpListingBridge, String> {
    runtime()
        .block_on(h.inner.list(&path))
        .map(|entries| SftpListingBridge { entries })
        .map_err(|e| e.to_string())
}

fn sftp_realpath(h: &SftpHandleBridge, path: String) -> Result<String, String> {
    runtime()
        .block_on(h.inner.realpath(&path))
        .map_err(|e| e.to_string())
}

fn sftp_stat(h: &SftpHandleBridge, path: String) -> Result<FileStatBridge, String> {
    runtime()
        .block_on(h.inner.stat(&path))
        .map(|s| FileStatBridge {
            size: s.size,
            mtime: s.mtime,
            mode: s.mode,
            is_dir: s.is_dir,
        })
        .map_err(|e| e.to_string())
}

fn sftp_mkdir(h: &SftpHandleBridge, path: String) -> Result<(), String> {
    runtime()
        .block_on(h.inner.mkdir(&path))
        .map_err(|e| e.to_string())
}

fn sftp_rename(h: &SftpHandleBridge, from: String, to: String) -> Result<(), String> {
    runtime()
        .block_on(h.inner.rename(&from, &to))
        .map_err(|e| e.to_string())
}

fn sftp_unlink(h: &SftpHandleBridge, path: String) -> Result<(), String> {
    runtime()
        .block_on(h.inner.unlink(&path))
        .map_err(|e| e.to_string())
}

fn sftp_read_head(h: &SftpHandleBridge, path: String, max: u32) -> Result<Vec<u8>, String> {
    runtime()
        .block_on(h.inner.read_head(&path, max))
        .map_err(|e| e.to_string())
}

fn cancel_flag_new() -> CancelFlagBridge {
    CancelFlagBridge {
        inner: ssh::CancelFlag::new(),
    }
}

fn cancel_flag_cancel(f: &CancelFlagBridge) {
    f.inner.cancel();
}

fn progress_sink_for_transfer(progress: &Arc<AtomicU64>) -> ssh::ProgressSink {
    use std::sync::atomic::Ordering;

    progress.store(0, Ordering::Relaxed);
    let progress = Arc::clone(progress);
    Arc::new(move |n| {
        progress.store(n, Ordering::Relaxed);
    })
}

fn sftp_download_sync(
    h: &SftpHandleBridge,
    remote: String,
    local: String,
    cancel: &CancelFlagBridge,
) -> Result<(), String> {
    let sink = progress_sink_for_transfer(&h.progress);
    runtime()
        .block_on(h.inner.download(
            &remote,
            std::path::Path::new(&local),
            sink,
            cancel.inner.clone(),
        ))
        .map_err(|e| e.to_string())
}

fn sftp_upload_sync(
    h: &SftpHandleBridge,
    local: String,
    remote: String,
    cancel: &CancelFlagBridge,
) -> Result<(), String> {
    let sink = progress_sink_for_transfer(&h.progress);
    runtime()
        .block_on(h.inner.upload(
            std::path::Path::new(&local),
            &remote,
            sink,
            cancel.inner.clone(),
        ))
        .map_err(|e| e.to_string())
}

fn sftp_progress_poll(h: &SftpHandleBridge) -> u64 {
    h.progress.load(Ordering::Relaxed)
}

fn ssh_sftp_walk_start(
    h: &SftpHandleBridge,
    root: String,
    pattern: String,
    max_depth: u32,
    cap: u32,
    include_hidden: bool,
) -> SftpWalkSessionBridge {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let cancel = Arc::new(AtomicBool::new(false));
    let cancel_task = Arc::clone(&cancel);
    let sftp = h.inner.clone();
    let join = runtime().spawn(async move {
        sftp.walk(
            &root,
            ssh::WalkOptions {
                max_depth,
                cap: cap as usize,
                include_hidden,
                pattern,
            },
            cancel_task,
            move |m| {
                let _ = tx.send(m);
            },
        )
        .await
        .map_err(|e| e.to_string())
    });

    SftpWalkSessionBridge {
        rx: Mutex::new(rx),
        cancel,
        join: Mutex::new(Some(join)),
    }
}

fn ssh_sftp_walk_drain(session: &SftpWalkSessionBridge, max: u32) -> SftpWalkBatchBridge {
    let mut matches = Vec::new();
    if max == 0 {
        return SftpWalkBatchBridge { matches };
    }

    let mut rx = session.rx.lock().unwrap();
    while matches.len() < max as usize {
        match rx.try_recv() {
            Ok(m) => matches.push(m),
            Err(_) => break,
        }
    }

    SftpWalkBatchBridge { matches }
}

fn ssh_sftp_walk_cancel(session: &SftpWalkSessionBridge) {
    session.cancel.store(true, Ordering::Relaxed);
}

fn ssh_sftp_walk_is_done(session: &SftpWalkSessionBridge) -> bool {
    session
        .join
        .lock()
        .map(|join| join.as_ref().map(|h| h.is_finished()).unwrap_or(true))
        .unwrap_or(true)
}

// ---------------------------------------------------------------------------
// SftpListingBridge accessors (free functions exposed via extern "Rust")
// ---------------------------------------------------------------------------

fn sftp_listing_len(listing: &SftpListingBridge) -> usize {
    listing.entries.len()
}

/// Returns an empty entry if `index >= len()`. Out-of-bounds access
/// degrades to empty rather than panicking the host process.
fn sftp_listing_entry(listing: &SftpListingBridge, index: usize) -> ffi::FileEntryBridge {
    if index >= listing.entries.len() {
        return ffi::FileEntryBridge {
            name: String::new(),
            is_dir: false,
            size: 0,
            mtime: 0,
            mode: 0,
        };
    }
    let e = &listing.entries[index];
    ffi::FileEntryBridge {
        name: e.name.clone(),
        is_dir: e.is_dir,
        size: e.size,
        mtime: e.mtime,
        mode: e.mode,
    }
}

fn sftp_walk_batch_len(batch: &SftpWalkBatchBridge) -> usize {
    batch.matches.len()
}

fn sftp_walk_batch_entry(batch: &SftpWalkBatchBridge, index: usize) -> ffi::WalkMatchBridge {
    if index >= batch.matches.len() {
        return ffi::WalkMatchBridge {
            path: String::new(),
            name: String::new(),
            size: 0,
            is_directory: false,
            mtime: 0,
        };
    }

    walk_match_to_bridge(&batch.matches[index])
}

fn walk_match_to_bridge(m: &ssh::WalkMatch) -> ffi::WalkMatchBridge {
    ffi::WalkMatchBridge {
        path: m.path.clone(),
        name: m.name.clone(),
        size: m.size,
        is_directory: m.is_directory,
        mtime: m.mtime.unwrap_or(0),
    }
}

// ---------------------------------------------------------------------------
// ConnKey conversion helpers
// ---------------------------------------------------------------------------

fn key_to_bridge(key: &ssh::ConnKey) -> ConnKeyBridge {
    ConnKeyBridge {
        user: key.user.clone(),
        hostname: key.hostname.clone(),
        port: key.port,
        config_hash_hex: hex::encode(key.config_hash),
    }
}

fn bridge_to_key(key: ConnKeyBridge) -> ssh::ConnKey {
    let mut config_hash = [0u8; 16];
    if let Ok(bytes) = hex::decode(&key.config_hash_hex) {
        let n = bytes.len().min(16);
        config_hash[..n].copy_from_slice(&bytes[..n]);
    }
    ssh::ConnKey {
        user: key.user,
        hostname: key.hostname,
        port: key.port,
        config_hash,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    #[test]
    fn progress_sink_for_transfer_resets_stale_counter_before_use() {
        let progress = Arc::new(AtomicU64::new(123));

        let sink = progress_sink_for_transfer(&progress);

        assert_eq!(progress.load(Ordering::Relaxed), 0);
        sink(456);
        assert_eq!(progress.load(Ordering::Relaxed), 456);
    }

    #[test]
    fn walk_session_api_symbols_exist() {
        let _start: fn(&SftpHandleBridge, String, String, u32, u32, bool) -> SftpWalkSessionBridge =
            ssh_sftp_walk_start;
        let _drain: fn(&SftpWalkSessionBridge, u32) -> SftpWalkBatchBridge = ssh_sftp_walk_drain;
        let _cancel: fn(&SftpWalkSessionBridge) = ssh_sftp_walk_cancel;
        let _is_done: fn(&SftpWalkSessionBridge) -> bool = ssh_sftp_walk_is_done;
    }
}
