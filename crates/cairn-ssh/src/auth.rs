use crate::error::SshError;
use crate::types::ResolvedConfig;
use async_trait::async_trait;
use std::path::{Path, PathBuf};

#[async_trait]
pub trait PassphraseResolver: Send + Sync {
    /// Returns the passphrase for a key file, or None if user cancels.
    async fn resolve(&self, key_path: &Path) -> Option<String>;
}

/// Ordered list of auth methods we attempt, in priority order.
pub fn planned_methods(resolved: &ResolvedConfig) -> Vec<AuthMethod> {
    let mut out = Vec::new();
    if resolved.identity_agent.is_some() || std::env::var_os("SSH_AUTH_SOCK").is_some() {
        out.push(AuthMethod::Agent);
    }
    for id in &resolved.identity_files {
        out.push(AuthMethod::KeyFile(id.clone()));
    }
    out
}

#[derive(Debug, Clone)]
pub enum AuthMethod {
    Agent,
    KeyFile(PathBuf),
}

pub fn auth_kind_not_supported(kind: &str) -> SshError {
    let kind_static: &'static str = match kind {
        "password" => "password",
        "keyboard-interactive" => "keyboard-interactive",
        _ => "unknown",
    };
    SshError::AuthKindNotSupported { kind: kind_static }
}

/// Helper: consolidate list of tried methods into a single "tried: X, Y" string.
pub fn format_tried(methods: &[AuthMethod]) -> String {
    methods
        .iter()
        .map(|m| match m {
            AuthMethod::Agent => "agent".to_string(),
            AuthMethod::KeyFile(p) => format!("key {}", p.display()),
        })
        .collect::<Vec<_>>()
        .join(", ")
}
