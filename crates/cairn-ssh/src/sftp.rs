use std::sync::Arc;

use russh_sftp::client::error::Error as SftpError;
use russh_sftp::client::rawsession::RawSftpSession;
use russh_sftp::protocol::{FileAttributes, OpenFlags, StatusCode};

use crate::error::{Result, SshError};
use crate::pool::SshPool;
use crate::transfer::{CancelFlag, ProgressSink};
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

    /// Resolve a server-side path to its absolute canonical form.
    /// Used to translate "." / "~" / relative paths into a stable absolute
    /// path — SFTP itself has no ~ expansion; the shell does. Right after
    /// login, `canonicalize(".")` returns the user's home directory.
    pub async fn realpath(&self, path: &str) -> Result<String> {
        self.pool.touch(&self.key);
        let name = self.session.realpath(path).await.map_err(map_sftp_err)?;
        // RawSftpSession.realpath returns a Name with one file entry — its
        // filename field carries the canonical absolute path.
        name.files
            .into_iter()
            .next()
            .map(|f| f.filename)
            .ok_or(SshError::SftpProtocol("realpath: empty response".into()))
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
                Err(SftpError::Status(ref status)) if status.status_code == StatusCode::Eof => {
                    break;
                }
                Err(e) => return Err(map_sftp_err(e)),
            }
        }

        self.session.close(handle).await.map_err(map_sftp_err)?;

        self.pool.touch(&self.key);
        Ok(entries)
    }

    // -----------------------------------------------------------------------
    // Stat
    // -----------------------------------------------------------------------

    /// Return metadata for a single remote path (follows symlinks).
    pub async fn stat(&self, path: &str) -> Result<RemoteStat> {
        self.pool.touch(&self.key);

        let attrs = self.session.stat(path).await.map_err(map_sftp_err)?.attrs;

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

        self.session.rename(from, to).await.map_err(map_sftp_err)?;

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

        self.session.rmdir(path).await.map_err(map_sftp_err)?;

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
            Err(SftpError::Status(ref status)) if status.status_code == StatusCode::Eof => {
                vec![]
            }
            Err(e) => return Err(map_sftp_err(e)),
        };

        self.pool.touch(&self.key);
        Ok(data)
    }

    // -----------------------------------------------------------------------
    // Download (remote → local)
    // -----------------------------------------------------------------------

    /// Download a remote file to a local path.
    ///
    /// Reads in 256 KiB chunks. Before each chunk read the `cancel` flag is
    /// checked; if set, the function returns [`SshError::Cancelled`] and
    /// leaves the (partial) destination file in place so the caller can
    /// inspect what arrived.
    ///
    /// `progress` is called after each successful chunk with the running
    /// byte total so a Swift actor can update a progress bar without
    /// touching the transfer loop.
    pub async fn download(
        &self,
        remote_path: &str,
        local_path: &std::path::Path,
        progress: ProgressSink,
        cancel: CancelFlag,
    ) -> Result<()> {
        use tokio::io::AsyncWriteExt;

        self.pool.touch(&self.key);

        if let Some(parent) = local_path.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }

        let mut dest = tokio::fs::File::create(local_path)
            .await
            .map_err(SshError::Io)?;

        let handle = self
            .session
            .open(remote_path, OpenFlags::READ, FileAttributes::empty())
            .await
            .map_err(map_sftp_err)?
            .handle;

        const CHUNK: u32 = 256 * 1024;
        let mut offset: u64 = 0;
        let mut total: u64 = 0;

        loop {
            if cancel.is_cancelled() {
                let _ = self.session.close(handle.as_str()).await;
                return Err(SshError::Cancelled);
            }

            match self.session.read(handle.as_str(), offset, CHUNK).await {
                Ok(data) => {
                    let n = data.data.len() as u64;
                    dest.write_all(&data.data).await.map_err(SshError::Io)?;
                    offset += n;
                    total += n;
                    progress(total);
                    // If server returned fewer bytes than requested and the
                    // next read would be at the same offset it's actually EOF;
                    // but in SFTP the server will send an EOF status on the
                    // following read, so just keep looping.
                    if n == 0 {
                        break;
                    }
                }
                Err(SftpError::Status(ref status)) if status.status_code == StatusCode::Eof => {
                    break;
                }
                Err(e) => {
                    let _ = self.session.close(handle.as_str()).await;
                    return Err(map_sftp_err(e));
                }
            }
        }

        let _ = self.session.close(handle.as_str()).await;
        dest.flush().await.map_err(SshError::Io)?;

        self.pool.touch(&self.key);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Upload (local → remote)
    // -----------------------------------------------------------------------

    /// Upload a local file to a remote path.
    ///
    /// Writes in 256 KiB chunks. Before each chunk write the `cancel` flag
    /// is checked; if set, the function returns [`SshError::Cancelled`] and
    /// leaves the (partial) remote file in place.
    ///
    /// `progress` is called after each successful chunk with the running
    /// byte total.
    pub async fn upload(
        &self,
        local_path: &std::path::Path,
        remote_path: &str,
        progress: ProgressSink,
        cancel: CancelFlag,
    ) -> Result<()> {
        use tokio::io::AsyncReadExt;

        self.pool.touch(&self.key);

        let mut src = tokio::fs::File::open(local_path)
            .await
            .map_err(SshError::Io)?;

        let handle = self
            .session
            .open(
                remote_path,
                OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::TRUNCATE,
                FileAttributes::empty(),
            )
            .await
            .map_err(map_sftp_err)?
            .handle;

        const CHUNK: usize = 256 * 1024;
        let mut buf = vec![0u8; CHUNK];
        let mut offset: u64 = 0;
        let mut total: u64 = 0;

        loop {
            if cancel.is_cancelled() {
                let _ = self.session.close(handle.as_str()).await;
                return Err(SshError::Cancelled);
            }

            let n = src.read(&mut buf).await.map_err(SshError::Io)?;
            if n == 0 {
                break;
            }

            self.session
                .write(handle.as_str(), offset, buf[..n].to_vec())
                .await
                .map_err(map_sftp_err)?;

            offset += n as u64;
            total += n as u64;
            progress(total);
        }

        let _ = self.session.close(handle.as_str()).await;

        self.pool.touch(&self.key);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Server-side copy
    // -----------------------------------------------------------------------

    /// Attempt an in-server copy using the `copy-data` extension (OpenSSH
    /// 8.8+). Returns [`SshError::SftpProtocol`] if the server does not
    /// support the extension so the Swift layer can fall back to a
    /// client-mediated download + upload.
    pub async fn server_side_copy(&self, src_path: &str, dst_path: &str) -> Result<()> {
        if !self.supports_copy_data {
            return Err(SshError::SftpProtocol(
                "copy-data extension not supported by server".into(),
            ));
        }

        self.pool.touch(&self.key);

        // Open source for reading.
        let read_handle = self
            .session
            .open(src_path, OpenFlags::READ, FileAttributes::empty())
            .await
            .map_err(map_sftp_err)?
            .handle;

        // Open (or create) destination for writing.
        let write_handle = self
            .session
            .open(
                dst_path,
                OpenFlags::WRITE | OpenFlags::CREATE | OpenFlags::TRUNCATE,
                FileAttributes::empty(),
            )
            .await
            .map_err(map_sftp_err)?
            .handle;

        // copy-data payload: read_handle (string), read_offset (uint64),
        // read_length (uint64, 0 = whole file), write_handle (string),
        // write_offset (uint64).  Serialised as SFTP wire encoding.
        let payload = build_copy_data_payload(&read_handle, 0, 0, &write_handle, 0);

        let result = self
            .session
            .extended("copy-data", payload)
            .await
            .map_err(map_sftp_err);

        let _ = self.session.close(read_handle.as_str()).await;
        let _ = self.session.close(write_handle.as_str()).await;

        result?;

        self.pool.touch(&self.key);
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// copy-data payload builder
// ---------------------------------------------------------------------------

/// Encode the `copy-data` extended request payload according to
/// draft-ietf-secsh-filexfer-extensions-00 §7.  The wire format is:
///
/// ```text
/// string   read-from-handle
/// uint64   read-from-offset
/// uint64   read-data-length   (0 = copy to EOF)
/// string   write-to-handle
/// uint64   write-to-offset
/// ```
fn build_copy_data_payload(
    read_handle: &str,
    read_offset: u64,
    read_length: u64,
    write_handle: &str,
    write_offset: u64,
) -> Vec<u8> {
    let mut buf = Vec::new();
    push_sftp_string(&mut buf, read_handle.as_bytes());
    buf.extend_from_slice(&read_offset.to_be_bytes());
    buf.extend_from_slice(&read_length.to_be_bytes());
    push_sftp_string(&mut buf, write_handle.as_bytes());
    buf.extend_from_slice(&write_offset.to_be_bytes());
    buf
}

/// SFTP wire-encodes a `string` as a 4-byte big-endian length followed by
/// the raw bytes.
fn push_sftp_string(buf: &mut Vec<u8>, s: &[u8]) {
    buf.extend_from_slice(&(s.len() as u32).to_be_bytes());
    buf.extend_from_slice(s);
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
            StatusCode::PermissionDenied => SshError::SftpPermissionDenied(status.error_message),
            StatusCode::NoSuchFile => SshError::SftpNotFound(status.error_message),
            other => SshError::SftpProtocol(format!("{other:?}: {}", status.error_message)),
        },
        SftpError::Timeout => SshError::SftpProtocol("sftp timeout".into()),
        other => SshError::SftpProtocol(other.to_string()),
    }
}
