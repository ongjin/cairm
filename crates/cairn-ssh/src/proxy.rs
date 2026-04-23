use crate::error::{Result, SshError};
use std::pin::Pin;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};

/// Expand OpenSSH ProxyCommand tokens: %h, %p, %r (host/port/user).
pub fn expand_tokens(cmd: &str, host: &str, port: u16, user: &str) -> String {
    cmd.replace("%h", host)
        .replace("%p", &port.to_string())
        .replace("%r", user)
}

/// Spawn the proxy command under /bin/sh and return an AsyncRead + AsyncWrite
/// stream composed of the child's stdout + stdin. Stderr is drained to an
/// in-memory buffer (capped at 8 KiB) for diagnostic reporting on failure.
pub async fn dial_with_proxy(
    proxy_cmd: &str,
    host: &str,
    port: u16,
    user: &str,
) -> Result<ProxyStream> {
    let expanded = expand_tokens(proxy_cmd, host, port, user);
    let mut child = Command::new("/bin/sh")
        .arg("-c")
        .arg(&expanded)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .map_err(|e| SshError::ProxyCommandSpawn {
            cmd: expanded.clone(),
            source: e,
        })?;

    let stderr_buf: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
    if let Some(stderr) = child.stderr.take() {
        let buf = stderr_buf.clone();
        tokio::spawn(async move {
            use tokio::io::AsyncReadExt;
            let mut r = stderr;
            let mut tmp = [0u8; 512];
            loop {
                match r.read(&mut tmp).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        let mut g = buf.lock().unwrap();
                        let room = 8192usize.saturating_sub(g.len());
                        if room == 0 {
                            continue;
                        }
                        let take = n.min(room);
                        g.extend_from_slice(&tmp[..take]);
                    }
                }
            }
        });
    }

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| SshError::Russh("proxy: no stdout".into()))?;
    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| SshError::Russh("proxy: no stdin".into()))?;

    // Give the shell a brief moment to fail on a bad command so we can
    // surface a useful error rather than returning a dead stream.
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    match child.try_wait() {
        Ok(Some(status)) if !status.success() => {
            // Drain stderr for diagnostics (best-effort, brief wait).
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            let stderr_preview = {
                let g = stderr_buf.lock().unwrap();
                let s = String::from_utf8_lossy(&g).into_owned();
                let mut s = s;
                s.truncate(500);
                s
            };
            return Err(SshError::ProxyCommandFailed {
                exit_code: status.code().unwrap_or(-1),
                stderr_preview,
            });
        }
        _ => {}
    }

    Ok(ProxyStream {
        child,
        stdout,
        stdin,
        stderr_buf,
    })
}

pub struct ProxyStream {
    child: Child,
    stdout: ChildStdout,
    stdin: ChildStdin,
    stderr_buf: Arc<Mutex<Vec<u8>>>,
}

impl ProxyStream {
    /// Latest stderr content captured from the child, up to 8 KiB.
    pub fn stderr_snapshot(&self) -> Vec<u8> {
        self.stderr_buf.lock().unwrap().clone()
    }

    /// Check if child exited with failure and surface it as an error.
    pub async fn ensure_running(&mut self) -> Result<()> {
        match self.child.try_wait() {
            Ok(Some(status)) if !status.success() => {
                let stderr = String::from_utf8_lossy(&self.stderr_snapshot()).into_owned();
                let mut preview = stderr;
                preview.truncate(500);
                Err(SshError::ProxyCommandFailed {
                    exit_code: status.code().unwrap_or(-1),
                    stderr_preview: preview,
                })
            }
            _ => Ok(()),
        }
    }
}

impl AsyncRead for ProxyStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stdout).poll_read(cx, buf)
    }
}

impl AsyncWrite for ProxyStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.stdin).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stdin).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.stdin).poll_shutdown(cx)
    }
}
