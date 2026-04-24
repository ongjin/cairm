use crate::error::SshError;
use crate::types::ResolvedConfig;
use async_trait::async_trait;
use std::path::{Path, PathBuf};

#[async_trait]
pub trait PassphraseResolver: Send + Sync {
    /// Returns the passphrase for a key file, or None if user cancels.
    async fn resolve(&self, key_path: &Path) -> Option<String>;
}

#[async_trait]
pub trait PasswordResolver: Send + Sync {
    /// Returns the password for a host+user, or None if user cancels.
    /// Called when the preset password fails, or when password auth was selected
    /// but no preset was provided.
    async fn resolve(&self, host: &str, user: &str) -> Option<String>;
}

/// Ordered list of auth methods we attempt, in priority order. Password (if a
/// preset was supplied via `ResolvedConfig.password`) is unshifted to the front
/// so the user's explicit choice wins over Agent/Key defaults.
pub fn planned_methods(resolved: &ResolvedConfig) -> Vec<AuthMethod> {
    let mut out = Vec::new();
    let has_explicit_password = resolved.password.is_some();
    if let Some(pw) = &resolved.password {
        out.push(AuthMethod::Password(pw.clone()));
    }
    if resolved.identity_agent.is_some() || std::env::var_os("SSH_AUTH_SOCK").is_some() {
        out.push(AuthMethod::Agent);
    }
    for id in &resolved.identity_files {
        out.push(AuthMethod::KeyFile(id.clone()));
    }
    if !has_explicit_password && prefers_password_auth(resolved) {
        out.push(AuthMethod::Password(String::new()));
    }
    out
}

fn prefers_password_auth(resolved: &ResolvedConfig) -> bool {
    resolved.preferred_authentications.iter().any(|auth| {
        auth.eq_ignore_ascii_case("password")
            || auth.eq_ignore_ascii_case("keyboard-interactive")
    })
}

#[derive(Clone)]
pub enum AuthMethod {
    Agent,
    KeyFile(PathBuf),
    /// Carries the password value. Never printed — `Debug` and `format_tried`
    /// both redact the payload.
    Password(String),
}

impl std::fmt::Debug for AuthMethod {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Agent => write!(f, "Agent"),
            Self::KeyFile(p) => f.debug_tuple("KeyFile").field(p).finish(),
            Self::Password(_) => write!(f, "Password(<redacted>)"),
        }
    }
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
            AuthMethod::Password(_) => "password".to_string(),
        })
        .collect::<Vec<_>>()
        .join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{ResolvedConfig, StrictMode};
    use std::path::PathBuf;
    use std::time::Duration;

    fn base_config() -> ResolvedConfig {
        ResolvedConfig {
            hostname: "example.com".into(),
            port: 22,
            user: "alice".into(),
            identity_files: Vec::new(),
            identity_agent: None,
            proxy_command: None,
            proxy_jump: None,
            server_alive_interval: Duration::from_secs(30),
            server_alive_count_max: 3,
            strict_host_key_checking: StrictMode::Ask,
            user_known_hosts_file: Vec::new(),
            global_known_hosts_file: Vec::new(),
            host_key_algorithms: Vec::new(),
            preferred_authentications: Vec::new(),
            compression: false,
            hash_known_hosts: false,
            password: None,
        }
    }

    #[test]
    fn planned_methods_prompts_for_password_when_preferred_without_preset() {
        let mut cfg = base_config();
        cfg.preferred_authentications = vec!["publickey".into(), "password".into()];

        let methods = planned_methods(&cfg);

        assert!(methods
            .iter()
            .any(|m| matches!(m, AuthMethod::Password(p) if p.is_empty())));
    }

    #[test]
    fn planned_methods_prompts_for_keyboard_interactive_when_preferred_without_preset() {
        let mut cfg = base_config();
        cfg.preferred_authentications = vec!["keyboard-interactive".into()];

        let methods = planned_methods(&cfg);

        assert!(methods
            .iter()
            .any(|m| matches!(m, AuthMethod::Password(p) if p.is_empty())));
    }

    #[test]
    fn planned_methods_keeps_explicit_password_first() {
        let mut cfg = base_config();
        cfg.password = Some("secret".into());
        cfg.identity_agent = Some(PathBuf::from("/tmp/agent.sock"));
        cfg.preferred_authentications = vec!["password".into()];

        let methods = planned_methods(&cfg);

        assert!(matches!(methods.first(), Some(AuthMethod::Password(p)) if p == "secret"));
        assert_eq!(format_tried(&methods), "password, agent");
    }
}
