use std::io;
use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SshError {
    #[error("Couldn't resolve ssh_config for {host}: {msg}")]
    ConfigResolution { host: String, msg: String },

    #[error("Proxy command failed (exit {exit_code}): {stderr_preview}")]
    ProxyCommandFailed { exit_code: i32, stderr_preview: String },

    #[error("Couldn't spawn proxy command ({cmd}): {source}")]
    ProxyCommandSpawn {
        cmd: String,
        #[source]
        source: io::Error,
    },

    #[error("ProxyJump without ProxyCommand is not supported in v1")]
    ProxyJumpNotSupported,

    #[error("Network unreachable: {host}:{port}")]
    NetworkUnreachable { host: String, port: u16 },

    #[error("Host key mismatch for {host} — possible MITM")]
    HostKeyMismatch { host: String },

    #[error("Host key not accepted")]
    HostKeyRejected,

    #[error("No authentication method succeeded (tried: {tried})")]
    AuthNoMethods { tried: String },

    #[error("Server requires {kind} authentication — not supported in v1")]
    AuthKindNotSupported { kind: &'static str },

    #[error("Couldn't unlock key file {path}")]
    KeyPassphraseFailed { path: PathBuf },

    #[error("SFTP: {0}")]
    SftpProtocol(String),

    #[error("Permission denied: {0}")]
    SftpPermissionDenied(String),

    #[error("Not found: {0}")]
    SftpNotFound(String),

    #[error("No space left on remote")]
    SftpNoSpace,

    #[error("Connection to {host} lost")]
    ConnectionLost { host: String },

    #[error("Cancelled")]
    Cancelled,

    #[error(transparent)]
    Io(#[from] io::Error),

    #[error("Russh: {0}")]
    Russh(String),
}

pub type Result<T> = std::result::Result<T, SshError>;
