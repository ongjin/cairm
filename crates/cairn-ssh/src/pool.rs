use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use parking_lot::Mutex;
use russh::client;
use russh::keys::{self, key, PublicKeyBase64};
use tracing::{debug, warn};

use crate::auth::{format_tried, planned_methods, AuthMethod, PassphraseResolver};
use crate::config::resolve_host;
use crate::error::{Result, SshError};
use crate::hostkey::{HostKeyResolver, KnownHostsStore, KnownResult, TofuDecision};
use crate::types::{ConnKey, ConnectSpec, ResolvedConfig, StrictMode};

// ---------------------------------------------------------------------------
// Pool entry
// ---------------------------------------------------------------------------

/// Each SSH connection is stored as a `SharedHandle` so it can be cloned out
/// of the pool map and used independently in async code without holding the
/// pool-level parking_lot lock across await points.
pub(crate) type SharedHandle = Arc<tokio::sync::Mutex<client::Handle<CairnHandler>>>;

#[allow(dead_code)]
struct Entry {
    handle: SharedHandle,
    resolved: ResolvedConfig,
    last_used: Instant,
}

// ---------------------------------------------------------------------------
// Pool public API
// ---------------------------------------------------------------------------

/// A connection pool that deduplicates SSH sessions by [`ConnKey`].
/// Multiple tabs connecting to the same host share one russh handle.
pub struct SshPool {
    inner: Arc<Mutex<HashMap<ConnKey, Entry>>>,
}

impl Default for SshPool {
    fn default() -> Self {
        Self::new()
    }
}

impl SshPool {
    /// Create a new pool and spawn the background idle-reaper task.
    pub fn new() -> Self {
        let inner = Arc::new(Mutex::new(HashMap::<ConnKey, Entry>::new()));
        let reaper_ref = Arc::clone(&inner);
        tokio::spawn(async move {
            idle_reaper(reaper_ref).await;
        });
        Self { inner }
    }

    /// Open (or return an existing) SSH connection for the given spec.
    ///
    /// Applies user/port/identity overrides from `spec`, resolves the full
    /// config via `ssh -G`, then either returns an existing entry or dials a
    /// new connection.
    pub async fn connect(
        &self,
        spec: &ConnectSpec,
        passphrase: Arc<dyn PassphraseResolver>,
        host_key_resolver: Arc<dyn HostKeyResolver>,
    ) -> Result<ConnKey> {
        // Resolve via ssh -G, then apply overrides.
        let mut resolved = resolve_host(&spec.host_alias)?;
        if let Some(u) = &spec.user_override {
            resolved.user = u.clone();
        }
        if let Some(p) = spec.port_override {
            resolved.port = p;
        }
        if let Some(id) = &spec.identity_file_override {
            resolved.identity_files = vec![id.clone()];
        }
        if let Some(pc) = &spec.proxy_command_override {
            resolved.proxy_command = Some(pc.clone());
        }

        // Translate ProxyJump into an equivalent ProxyCommand. OpenSSH does
        // this internally; we do it here so the rest of the pipeline only has
        // to understand one mechanism. The outer `ssh -W` invocation reads
        // ~/.ssh/config itself so chained ProxyJump/ProxyCommand on the jump
        // host (e.g. cloudflared) resolves naturally.
        if resolved.proxy_command.is_none() {
            if let Some(jump) = &resolved.proxy_jump {
                resolved.proxy_command = Some(format!("ssh -W %h:%p {jump}"));
            }
        }

        let key = ConnKey::from_resolved(&resolved);

        // Fast path: entry already present and healthy.
        {
            let mut map = self.inner.lock();
            if let Some(e) = map.get_mut(&key) {
                let closed = e.handle.try_lock().is_ok_and(|h| h.is_closed());
                if !closed {
                    e.last_used = Instant::now();
                    return Ok(key);
                }
                // Handle is closed — remove stale entry and reconnect.
                map.remove(&key);
            }
        }

        // Slow path: dial a new connection.
        let handle = dial(&resolved, passphrase, host_key_resolver).await?;

        {
            let mut map = self.inner.lock();
            map.insert(
                key.clone(),
                Entry {
                    handle: Arc::new(tokio::sync::Mutex::new(handle)),
                    resolved,
                    last_used: Instant::now(),
                },
            );
        }

        Ok(key)
    }

    /// Borrow the session handle for `key` and execute `f` against it.
    ///
    /// Returns `None` if the key is no longer in the pool.
    pub fn with_handle<F, R>(&self, key: &ConnKey, f: F) -> Option<R>
    where
        F: FnOnce(&mut client::Handle<CairnHandler>) -> R,
    {
        let map = self.inner.lock();
        map.get(key).map(|e| {
            let mut guard = e.handle.blocking_lock();
            f(&mut guard)
        })
    }

    /// Clone the shared handle for `key` so callers can use it across async
    /// boundaries without holding the pool-level lock.
    ///
    /// Returns `None` if the key is no longer in the pool.
    pub(crate) fn clone_handle(&self, key: &ConnKey) -> Option<SharedHandle> {
        self.inner.lock().get(key).map(|e| Arc::clone(&e.handle))
    }

    /// Update the last-used timestamp for `key` (call on every SFTP op).
    pub fn touch(&self, key: &ConnKey) {
        let mut map = self.inner.lock();
        if let Some(e) = map.get_mut(key) {
            e.last_used = Instant::now();
        }
    }

    /// Gracefully disconnect a single session.
    pub async fn disconnect(&self, key: &ConnKey) {
        let handle = {
            let mut map = self.inner.lock();
            map.remove(key).map(|e| e.handle)
        };
        if let Some(h) = handle {
            let h = h.lock().await;
            let _ = h
                .disconnect(russh::Disconnect::ByApplication, "", "en")
                .await;
        }
    }

    /// Gracefully disconnect all sessions.
    pub async fn close_all(&self) {
        let entries: Vec<SharedHandle> = {
            let mut map = self.inner.lock();
            map.drain().map(|(_, v)| v.handle).collect()
        };
        for h in entries {
            let h = h.lock().await;
            let _ = h
                .disconnect(russh::Disconnect::ByApplication, "", "en")
                .await;
        }
    }

    /// Snapshot the set of active keys (for diagnostics / UI).
    pub fn snapshot_keys(&self) -> Vec<ConnKey> {
        self.inner.lock().keys().cloned().collect()
    }

    /// Open a fresh SSH session channel and request the SFTP subsystem.
    ///
    /// Returns the channel stream, ready to be passed to
    /// `RawSftpSession::new()` / `SftpSession::new()`. The pool-level lock is
    /// not held while awaiting the server confirmation.
    pub async fn open_sftp_channel(
        &self,
        key: &ConnKey,
    ) -> Result<russh::Channel<russh::client::Msg>> {
        let shared = self
            .clone_handle(key)
            .ok_or_else(|| SshError::ConnectionLost {
                host: key.hostname.clone(),
            })?;

        let channel = {
            let handle = shared.lock().await;
            handle
                .channel_open_session()
                .await
                .map_err(|e| SshError::Russh(e.to_string()))?
        };

        channel
            .request_subsystem(true, "sftp")
            .await
            .map_err(|e| SshError::Russh(e.to_string()))?;

        self.touch(key);
        Ok(channel)
    }
}

// ---------------------------------------------------------------------------
// Background idle reaper
// ---------------------------------------------------------------------------

const IDLE_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const REAP_INTERVAL: Duration = Duration::from_secs(60);

async fn idle_reaper(inner: Arc<Mutex<HashMap<ConnKey, Entry>>>) {
    loop {
        tokio::time::sleep(REAP_INTERVAL).await;
        let now = Instant::now();
        let stale: Vec<ConnKey> = {
            let map = inner.lock();
            map.iter()
                .filter(|(_, e)| {
                    let closed = e.handle.try_lock().is_ok_and(|h| h.is_closed());
                    closed || now.duration_since(e.last_used) >= IDLE_TIMEOUT
                })
                .map(|(k, _)| k.clone())
                .collect()
        };
        for key in stale {
            let entry = inner.lock().remove(&key);
            if let Some(e) = entry {
                debug!(
                    "idle-reap: disconnecting {}@{}:{}",
                    key.user, key.hostname, key.port
                );
                let h = e.handle.lock().await;
                let _ = h
                    .disconnect(russh::Disconnect::ByApplication, "", "en")
                    .await;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// CairnHandler — russh client::Handler implementation
// ---------------------------------------------------------------------------

/// russh handler that checks server keys against known_hosts.
pub struct CairnHandler {
    resolved: ResolvedConfig,
    known_hosts: KnownHostsStore,
    host_key_resolver: Arc<dyn HostKeyResolver>,
}

impl CairnHandler {
    fn new(resolved: &ResolvedConfig, host_key_resolver: Arc<dyn HostKeyResolver>) -> Self {
        let mut paths = resolved.user_known_hosts_file.clone();
        paths.extend_from_slice(&resolved.global_known_hosts_file);
        let known_hosts = KnownHostsStore::new(paths);
        Self {
            resolved: resolved.clone(),
            known_hosts,
            host_key_resolver,
        }
    }
}

#[async_trait]
impl client::Handler for CairnHandler {
    type Error = anyhow::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &key::PublicKey,
    ) -> std::result::Result<bool, Self::Error> {
        let algo = server_public_key.name();
        let blob = server_public_key.public_key_bytes();

        let host = &self.resolved.hostname;
        let port = self.resolved.port;

        let known = self.known_hosts.lookup(host, port, algo, &blob);

        match self.resolved.strict_host_key_checking {
            StrictMode::Yes => match &known {
                KnownResult::Match => Ok(true),
                KnownResult::NotFound => {
                    warn!("StrictMode=yes: unknown host key for {host}");
                    Ok(false)
                }
                KnownResult::Mismatch { .. } => {
                    warn!("StrictMode=yes: host key MISMATCH for {host}");
                    Ok(false)
                }
            },
            StrictMode::AcceptNew => match &known {
                KnownResult::Match => Ok(true),
                KnownResult::NotFound => {
                    // Auto-accept and save.
                    if let Err(e) = self.known_hosts.append(
                        host,
                        port,
                        algo,
                        &blob,
                        self.resolved.hash_known_hosts,
                    ) {
                        warn!("AcceptNew: couldn't save host key: {e}");
                    }
                    Ok(true)
                }
                KnownResult::Mismatch { .. } => {
                    warn!("AcceptNew: host key MISMATCH for {host}");
                    Ok(false)
                }
            },
            StrictMode::Ask => {
                let decision = self
                    .host_key_resolver
                    .resolve(host, port, algo, &blob, known.clone())
                    .await;
                match decision {
                    TofuDecision::Accept => Ok(true),
                    TofuDecision::AcceptAndSave => {
                        if let Err(e) = self.known_hosts.append(
                            host,
                            port,
                            algo,
                            &blob,
                            self.resolved.hash_known_hosts,
                        ) {
                            warn!("Ask/AcceptAndSave: couldn't save host key: {e}");
                        }
                        Ok(true)
                    }
                    TofuDecision::Reject => Ok(false),
                }
            }
            StrictMode::No => Ok(true),
        }
    }
}

// ---------------------------------------------------------------------------
// Dial — connect + authenticate
// ---------------------------------------------------------------------------

/// Maximum passphrase attempts for an encrypted key file.
const MAX_PASSPHRASE_ATTEMPTS: usize = 3;

async fn dial(
    resolved: &ResolvedConfig,
    passphrase: Arc<dyn PassphraseResolver>,
    host_key_resolver: Arc<dyn HostKeyResolver>,
) -> Result<client::Handle<CairnHandler>> {
    let handler = CairnHandler::new(resolved, host_key_resolver);

    let cfg = Arc::new(client::Config {
        keepalive_interval: Some(resolved.server_alive_interval),
        keepalive_max: resolved.server_alive_count_max as usize,
        ..client::Config::default()
    });

    // Establish transport (direct TCP or ProxyCommand).
    let mut handle = if let Some(proxy_cmd) = &resolved.proxy_command {
        let stream = crate::proxy::dial_with_proxy(
            proxy_cmd,
            &resolved.hostname,
            resolved.port,
            &resolved.user,
        )
        .await?;
        client::connect_stream(cfg, stream, handler)
            .await
            .map_err(|e| SshError::Russh(format!("{e:?}")))?
    } else {
        let addr = (resolved.hostname.as_str(), resolved.port);
        client::connect(cfg, addr, handler)
            .await
            .map_err(|e| SshError::Russh(format!("{e:?}")))?
    };

    // Authentication.
    let methods = planned_methods(resolved);
    let mut tried: Vec<AuthMethod> = Vec::new();

    for method in &methods {
        match method {
            AuthMethod::Agent => {
                if let Ok(authed) = try_agent_auth(&mut handle, &resolved.user).await {
                    if authed {
                        return Ok(handle);
                    }
                    tried.push(AuthMethod::Agent);
                } else {
                    tried.push(AuthMethod::Agent);
                }
            }
            AuthMethod::KeyFile(path) => {
                match try_key_auth(&mut handle, &resolved.user, path, &*passphrase).await {
                    Ok(true) => return Ok(handle),
                    Ok(false) => tried.push(AuthMethod::KeyFile(path.clone())),
                    Err(_) => tried.push(AuthMethod::KeyFile(path.clone())),
                }
            }
        }
    }

    Err(SshError::AuthNoMethods {
        tried: format_tried(&tried),
    })
}

// ---------------------------------------------------------------------------
// Agent authentication
// ---------------------------------------------------------------------------

async fn try_agent_auth(
    handle: &mut client::Handle<CairnHandler>,
    user: &str,
) -> std::result::Result<bool, anyhow::Error> {
    // Connect to the agent via SSH_AUTH_SOCK.
    #[cfg(unix)]
    {
        let mut agent = keys::agent::client::AgentClient::connect_env().await?;

        // Get list of public keys from agent.
        let identities = agent.request_identities().await?;

        for pub_key in identities {
            // authenticate_future takes ownership of the agent and returns it back.
            let (agent_back, result) = handle.authenticate_future(user, pub_key, agent).await;
            agent = agent_back;

            match result {
                Ok(true) => return Ok(true),
                Ok(false) => continue,
                Err(e) => {
                    debug!("agent auth attempt failed: {e:?}");
                    continue;
                }
            }
        }
        Ok(false)
    }

    #[cfg(not(unix))]
    {
        let _ = (handle, user);
        Ok(false)
    }
}

// ---------------------------------------------------------------------------
// Key-file authentication
// ---------------------------------------------------------------------------

async fn try_key_auth(
    handle: &mut client::Handle<CairnHandler>,
    user: &str,
    path: &Path,
    passphrase: &dyn PassphraseResolver,
) -> Result<bool> {
    // First, try without a passphrase.
    let key_pair = match keys::load_secret_key(path, None) {
        Ok(kp) => kp,
        Err(keys::Error::KeyIsEncrypted) => {
            // Encrypted key — prompt up to MAX_PASSPHRASE_ATTEMPTS times.
            let mut result = None;
            for _ in 0..MAX_PASSPHRASE_ATTEMPTS {
                let Some(phrase) = passphrase.resolve(path).await else {
                    // User cancelled.
                    return Err(SshError::Cancelled);
                };
                match keys::load_secret_key(path, Some(&phrase)) {
                    Ok(kp) => {
                        result = Some(kp);
                        break;
                    }
                    Err(keys::Error::KeyIsEncrypted) | Err(_) => {
                        // Wrong passphrase or other decode error — retry.
                        continue;
                    }
                }
            }
            match result {
                Some(kp) => kp,
                None => {
                    return Err(SshError::KeyPassphraseFailed {
                        path: path.to_path_buf(),
                    });
                }
            }
        }
        Err(e) => {
            debug!("couldn't load key {:?}: {e}", path);
            return Ok(false);
        }
    };

    let key_arc = Arc::new(key_pair);
    let authed = handle
        .authenticate_publickey(user, key_arc)
        .await
        .map_err(|e| SshError::Russh(format!("{e:?}")))?;

    Ok(authed)
}
