//! SSH/SFTP backend for Cairn. Config resolution is delegated to the system
//! `ssh -G` binary so ProxyCommand / ProxyJump / Match / Include work without
//! a Rust-side ssh_config parser.

pub mod config;
pub mod error;
pub mod hostkey;
pub mod known_hosts_hash;
pub mod types;

pub use config::{list_configured_hosts, resolve_host};
pub use error::{Result, SshError};
pub use hostkey::{HostKeyResolver, KnownHostsStore, KnownResult, TofuDecision, sha256_fingerprint};
pub use types::{ConnKey, ConnectSpec, ResolvedConfig, StrictMode};
