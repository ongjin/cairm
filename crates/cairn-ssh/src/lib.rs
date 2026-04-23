//! SSH/SFTP backend for Cairn. Config resolution is delegated to the system
//! `ssh -G` binary so ProxyCommand / ProxyJump / Match / Include work without
//! a Rust-side ssh_config parser.

pub mod config;
pub mod error;
pub mod types;

pub use config::{list_configured_hosts, resolve_host};
pub use error::{Result, SshError};
pub use types::{ConnKey, ConnectSpec, ResolvedConfig, StrictMode};
