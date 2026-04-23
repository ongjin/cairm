//! SSH/SFTP backend for Cairn. Config resolution is delegated to the system
//! `ssh -G` binary so ProxyCommand / ProxyJump / Match / Include work without
//! a Rust-side ssh_config parser.

pub mod auth;
pub mod config;
pub mod error;
pub mod hostkey;
pub mod known_hosts_hash;
pub mod pool;
pub mod proxy;
pub mod sftp;
pub mod transfer;
pub mod types;

pub use auth::PassphraseResolver;
pub use config::{list_configured_hosts, resolve_host};
pub use error::{Result, SshError};
pub use hostkey::{
    sha256_fingerprint, HostKeyResolver, KnownHostsStore, KnownResult, TofuDecision,
};
pub use pool::SshPool;
pub use sftp::{RemoteEntry, RemoteStat, SftpHandle};
pub use transfer::{CancelFlag, ProgressSink};
pub use types::{ConnKey, ConnectSpec, ResolvedConfig, StrictMode};
