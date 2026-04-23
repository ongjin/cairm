use crate::known_hosts_hash::match_hashed_entry;
use async_trait::async_trait;
use base64::prelude::*;
use sha2::{Digest, Sha256};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;

pub fn sha256_fingerprint(pubkey_blob: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(pubkey_blob);
    let digest = h.finalize();
    let b64 = BASE64_STANDARD_NO_PAD.encode(digest);
    format!("SHA256:{b64}")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KnownResult {
    Match,
    NotFound,
    Mismatch { stored_algo: String, stored_blob: Vec<u8> },
}

#[derive(Debug, Clone)]
pub enum TofuDecision {
    Accept,
    AcceptAndSave,
    Reject,
}

#[async_trait]
pub trait HostKeyResolver: Send + Sync {
    async fn resolve(
        &self,
        host: &str,
        port: u16,
        offered_algo: &str,
        offered_blob: &[u8],
        known: KnownResult,
    ) -> TofuDecision;
}

/// Reads user+global known_hosts files and answers match queries.
pub struct KnownHostsStore {
    pub paths: Vec<PathBuf>,
}

impl KnownHostsStore {
    pub fn new(paths: Vec<PathBuf>) -> Self {
        Self { paths }
    }

    pub fn lookup(&self, host: &str, port: u16, offered_algo: &str, offered_blob: &[u8]) -> KnownResult {
        let target = host_key(host, port);
        let mut mismatch: Option<(String, Vec<u8>)> = None;
        for p in &self.paths {
            let Ok(f) = File::open(p) else { continue; };
            for line in BufReader::new(f).lines().map_while(Result::ok) {
                let line = line.trim().to_string();
                if line.is_empty() || line.starts_with('#') { continue; }
                let parts: Vec<&str> = line.splitn(3, ' ').collect();
                if parts.len() < 3 { continue; }
                let (hosts_field, algo, b64) = (parts[0], parts[1], parts[2]);
                if !host_matches(hosts_field, host, port, &target) { continue; }
                let blob = match BASE64_STANDARD.decode(b64.split_whitespace().next().unwrap_or("")) {
                    Ok(v) => v, Err(_) => continue,
                };
                if algo == offered_algo && blob == offered_blob {
                    return KnownResult::Match;
                } else if algo == offered_algo {
                    mismatch = Some((algo.into(), blob));
                }
            }
        }
        match mismatch {
            Some((a, b)) => KnownResult::Mismatch { stored_algo: a, stored_blob: b },
            None         => KnownResult::NotFound,
        }
    }

    pub fn append(&self, host: &str, port: u16, algo: &str, blob: &[u8], hash_known_hosts: bool) -> std::io::Result<()> {
        let path = self.paths.first().ok_or_else(|| std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "no user_known_hosts_file configured"
        ))?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut f = open_mode_600(path)?;
        let host_field = if hash_known_hosts {
            hashed_host_field(host, port)
        } else {
            plain_host_field(host, port)
        };
        writeln!(f, "{host_field} {algo} {}", BASE64_STANDARD.encode(blob))?;
        Ok(())
    }
}

fn open_mode_600(path: &std::path::Path) -> std::io::Result<std::fs::File> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        OpenOptions::new().create(true).append(true).mode(0o600).open(path)
    }
    #[cfg(not(unix))]
    {
        OpenOptions::new().create(true).append(true).open(path)
    }
}

fn host_key(host: &str, port: u16) -> String {
    if port == 22 { host.into() } else { format!("[{host}]:{port}") }
}

fn host_matches(field: &str, host: &str, _port: u16, target: &str) -> bool {
    if field.starts_with("|1|") {
        return match_hashed_entry(field, target);
    }
    for p in field.split(',') {
        let p = p.trim();
        if p == target || p == host {
            return true;
        }
    }
    false
}

fn plain_host_field(host: &str, port: u16) -> String { host_key(host, port) }

fn hashed_host_field(host: &str, port: u16) -> String {
    use hmac::{Hmac, Mac};
    use rand::RngCore;
    use sha1::Sha1;
    type HmacSha1 = Hmac<Sha1>;
    let mut salt = [0u8; 20];
    rand::thread_rng().fill_bytes(&mut salt);
    let mut mac = HmacSha1::new_from_slice(&salt).expect("HMAC");
    mac.update(host_key(host, port).as_bytes());
    let digest = mac.finalize().into_bytes();
    format!("|1|{}|{}", BASE64_STANDARD.encode(salt), BASE64_STANDARD.encode(digest))
}
