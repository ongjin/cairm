use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StrictMode {
    Yes,
    AcceptNew,
    Ask,
    No,
}

#[derive(Debug, Clone)]
pub struct ResolvedConfig {
    pub hostname: String,
    pub port: u16,
    pub user: String,
    pub identity_files: Vec<PathBuf>,
    pub identity_agent: Option<PathBuf>,
    pub proxy_command: Option<String>,
    pub proxy_jump: Option<String>,
    pub server_alive_interval: Duration,
    pub server_alive_count_max: u32,
    pub strict_host_key_checking: StrictMode,
    pub user_known_hosts_file: Vec<PathBuf>,
    pub global_known_hosts_file: Vec<PathBuf>,
    pub host_key_algorithms: Vec<String>,
    pub preferred_authentications: Vec<String>,
    pub compression: bool,
    pub hash_known_hosts: bool,
}

#[derive(Debug, Clone, Hash, PartialEq, Eq)]
pub struct ConnKey {
    pub user: String,
    pub hostname: String,
    pub port: u16,
    pub config_hash: [u8; 16],
}

impl ConnKey {
    pub fn from_resolved(resolved: &ResolvedConfig) -> Self {
        use sha2::{Digest, Sha256};
        let mut h = Sha256::new();
        if let Some(pc) = &resolved.proxy_command {
            h.update(pc.as_bytes());
        }
        for id in &resolved.identity_files {
            h.update(id.to_string_lossy().as_bytes());
        }
        for algo in &resolved.host_key_algorithms {
            h.update(algo.as_bytes());
        }
        if let Some(ia) = &resolved.identity_agent {
            h.update(ia.to_string_lossy().as_bytes());
        }
        let full = h.finalize();
        let mut out = [0u8; 16];
        out.copy_from_slice(&full[..16]);
        Self {
            user: resolved.user.clone(),
            hostname: resolved.hostname.clone(),
            port: resolved.port,
            config_hash: out,
        }
    }
}

/// One-off connection spec — user may override user/host/port/path/proxy on
/// top of the ssh_config-resolved defaults. All overrides are optional.
#[derive(Debug, Clone)]
pub struct ConnectSpec {
    pub host_alias: String, // ssh_config 이름 or bare hostname
    pub user_override: Option<String>,
    pub port_override: Option<u16>,
    pub identity_file_override: Option<PathBuf>,
    pub proxy_command_override: Option<String>,
}
