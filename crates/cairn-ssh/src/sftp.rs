use std::sync::Arc;

use russh_sftp::client::error::Error as SftpError;
use russh_sftp::client::rawsession::RawSftpSession;
use russh_sftp::protocol::{FileAttributes, OpenFlags, StatusCode};

use crate::error::{Result, SshError};
use crate::pool::SshPool;
use crate::types::ConnKey;

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct RemoteEntry {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub mtime: i64,
    pub mode: u32,
}

#[derive(Debug, Clone)]
pub struct RemoteStat {
    pub size: u64,
    pub mtime: i64,
    pub mode: u32,
    pub is_dir: bool,
}

// ---------------------------------------------------------------------------
// SftpHandle
// ---------------------------------------------------------------------------

/// Wraps a russh-sftp [`RawSftpSession`] with pool-touch semantics.
///
/// Every operation calls [`SshPool::touch`] on the associated key so that
/// the pool's idle-reaper timer is reset on activity.
pub struct SftpHandle {
    pool: Arc<SshPool>,
    key: ConnKey,
    session: Arc<RawSftpSession>,
    supports_copy_data: bool,
}

impl SftpHandle {
    /// Open a new SFTP session for `key` using a fresh SSH channel.
    ///
    /// The connection must already exist in `pool` (i.e. `pool.connect()` was
    /// called previously). Opens one SSH channel, requests the sftp subsystem,
    /// then probes server extensions via the SFTP init handshake.
    pub async fn open(pool: Arc<SshPool>, key: ConnKey) -> Result<Self> {
        let channel = pool.open_sftp_channel(&key).await?;
        let stream = channel.into_stream();

        // Use RawSftpSession directly so we can inspect the Version.extensions
        // map from the init handshake — SftpSession wraps the same primitives
        // but doesn't expose them publicly.
        let raw = RawSftpSession::new(stream);
        let version = raw
            .init()
            .await
            .map_err(|e| SshError::SftpProtocol(e.to_string()))?;

        let supports_copy_data = version.extensions.contains_key("copy-data")
            || version.extensions.contains_key("copy-data@openssh.com");

        pool.touch(&key);

        Ok(Self {
            pool,
            key,
            session: Arc::new(raw),
            supports_copy_data,
        })
    }

    /// Returns `true` if the remote server advertised the `copy-data`
    /// extension (OpenSSH 8.8+). When `true`, the Swift paste layer can
    /// request a server-side copy instead of a client-mediated transfer.
    pub fn supports_server_side_copy(&self) -> bool {
        self.supports_copy_data
    }

    // -----------------------------------------------------------------------
    // Directory listing
    // -----------------------------------------------------------------------

    /// List the entries of `path`. Filters out `.` and `..` so call sites
    /// always receive a clean list of real entries.
    pub async fn list(&self, path: &str) -> Result<Vec<RemoteEntry>> {
        self.pool.touch(&self.key);

        let handle = self
            .session
            .opendir(path)
            .await
            .map_err(map_sftp_err)?
            .handle;

        let mut entries = Vec::new();

        loop {
            match self.session.readdir(handle.as_str()).await {
                Ok(name) => {
                    for file in name.files {
                        if file.filename == "." || file.filename == ".." {
                            continue;
                        }
                        entries.push(attrs_to_entry(file.filename, &file.attrs));
                    }
                }
                Err(SftpError::Status(ref status))
                    if status.status_code == StatusCode::Eof =>
                {
                    break;
                }
                Err(e) => return Err(map_sftp_err(e)),
            }
        }

        self.session
            .close(handle)
            .await
            .map_err(map_sftp_err)?;

        self.pool.touch(&self.key);
        Ok(entries)
    }

    // -----------------------------------------------------------------------
    // Stat
    // -----------------------------------------------------------------------

    /// Return metadata for a single remote path (follows symlinks).
    pub async fn stat(&self, path: &str) -> Result<RemoteStat> {
        self.pool.touch(&self.key);

        let attrs = self
            .session
            .stat(path)
            .await
            .map_err(map_sftp_err)?
            .attrs;

        self.pool.touch(&self.key);
        Ok(attrs_to_stat(&attrs))
    }

    // -----------------------------------------------------------------------
    // Mkdir
    // -----------------------------------------------------------------------

    /// Create a new directory at `path` with default permissions.
    pub async fn mkdir(&self, path: &str) -> Result<()> {
        self.pool.touch(&self.key);

        self.session
            .mkdir(path, FileAttributes::empty())
            .await
            .map_err(map_sftp_err)?;

        self.pool.touch(&self.key);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Rename
    // -----------------------------------------------------------------------

    /// Rename/move `from` to `to` on the remote server.
    pub async fn rename(&self, from: &str, to: &str) -> Result<()> {
        self.pool.touch(&self.key);

        self.session
            .rename(from, to)
            .await
            .map_err(map_sftp_err)?;

        self.pool.touch(&self.key);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Unlink
    // -----------------------------------------------------------------------

    /// Delete the entry at `path`. Tries `remove` (file) first; if that
    /// returns a Failure status, falls back to `rmdir` (directory). This
    /// gives the Swift side a single "delete path" verb.
    pub async fn unlink(&self, path: &str) -> Result<()> {
        self.pool.touch(&self.key);

        match self.session.remove(path).await {
            Ok(_) => {
                self.pool.touch(&self.key);
                return Ok(());
            }
            Err(SftpError::Status(ref status))
                if status.status_code == StatusCode::Failure
                    || status.status_code == StatusCode::NoSuchFile =>
            {
                // Might be a directory — fall through to rmdir.
            }
            Err(e) => return Err(map_sftp_err(e)),
        }

        self.session
            .rmdir(path)
            .await
            .map_err(map_sftp_err)?;

        self.pool.touch(&self.key);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Read head (text preview)
    // -----------------------------------------------------------------------

    /// Read up to `max` bytes from the beginning of `path`. Used for text
    /// preview / UTI sniffing without downloading the whole file.
    pub async fn read_head(&self, path: &str, max: u32) -> Result<Vec<u8>> {
        self.pool.touch(&self.key);

        let handle = self
            .session
            .open(path, OpenFlags::READ, FileAttributes::empty())
            .await
            .map_err(map_sftp_err)?
            .handle;

        let result = self.session.read(handle.as_str(), 0, max).await;

        // Always close the handle, even if read failed.
        let _ = self.session.close(handle.as_str()).await;

        let data = match result {
            Ok(d) => d.data,
            // EOF on a file shorter than `max` is fine — return what we got.
            Err(SftpError::Status(ref status))
                if status.status_code == StatusCode::Eof =>
            {
                vec![]
            }
            Err(e) => return Err(map_sftp_err(e)),
        };

        self.pool.touch(&self.key);
        Ok(data)
    }
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

fn attrs_to_entry(name: String, attrs: &FileAttributes) -> RemoteEntry {
    RemoteEntry {
        name,
        is_dir: attrs.is_dir(),
        size: attrs.size.unwrap_or(0),
        mtime: attrs.mtime.unwrap_or(0) as i64,
        mode: attrs.permissions.unwrap_or(0),
    }
}

fn attrs_to_stat(attrs: &FileAttributes) -> RemoteStat {
    RemoteStat {
        size: attrs.size.unwrap_or(0),
        mtime: attrs.mtime.unwrap_or(0) as i64,
        mode: attrs.permissions.unwrap_or(0),
        is_dir: attrs.is_dir(),
    }
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

fn map_sftp_err(e: SftpError) -> SshError {
    match e {
        SftpError::Status(status) => match status.status_code {
            StatusCode::PermissionDenied => {
                SshError::SftpPermissionDenied(status.error_message)
            }
            StatusCode::NoSuchFile => SshError::SftpNotFound(status.error_message),
            other => SshError::SftpProtocol(format!("{other:?}: {}", status.error_message)),
        },
        SftpError::Timeout => SshError::SftpProtocol("sftp timeout".into()),
        other => SshError::SftpProtocol(other.to_string()),
    }
}
