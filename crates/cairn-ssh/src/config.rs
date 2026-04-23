use crate::error::{Result, SshError};
use crate::types::{ResolvedConfig, StrictMode};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

/// Resolve a host alias to a fully-expanded config via `ssh -G <host>`.
/// This delegates all ssh_config semantics (ProxyCommand, ProxyJump, Match,
/// Include, wildcards) to the system OpenSSH binary.
pub fn resolve_host(host: &str) -> Result<ResolvedConfig> {
    let out = Command::new("/usr/bin/ssh")
        .arg("-G")
        .arg(host)
        .output()
        .map_err(|e| SshError::ConfigResolution {
            host: host.into(),
            msg: format!("spawn ssh -G: {e}"),
        })?;
    if !out.status.success() {
        return Err(SshError::ConfigResolution {
            host: host.into(),
            msg: String::from_utf8_lossy(&out.stderr).into_owned(),
        });
    }
    parse_ssh_g_output(&String::from_utf8_lossy(&out.stdout))
}

pub fn parse_ssh_g_output(out: &str) -> Result<ResolvedConfig> {
    let mut kv: HashMap<&str, Vec<&str>> = HashMap::new();
    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.splitn(2, ' ');
        let k = parts.next().unwrap_or("");
        let v = parts.next().unwrap_or("");
        kv.entry(k).or_default().push(v);
    }

    let first = |k: &str| kv.get(k).and_then(|v| v.first().copied()).unwrap_or("");
    let all = |k: &str| kv.get(k).cloned().unwrap_or_default();

    let hostname = first("hostname").to_string();
    if hostname.is_empty() {
        return Err(SshError::ConfigResolution {
            host: "<unknown>".into(),
            msg: "no hostname in output".into(),
        });
    }

    let port: u16 = first("port").parse().unwrap_or(22);
    let user = {
        let u = first("user");
        if u.is_empty() {
            std::env::var("USER").unwrap_or_default()
        } else {
            u.into()
        }
    };

    let identity_files = all("identityfile")
        .into_iter()
        .map(expand_tilde)
        .collect();

    let identity_agent = {
        let v = first("identityagent");
        if v.is_empty() || v.eq_ignore_ascii_case("none") {
            None
        } else if v == "SSH_AUTH_SOCK" {
            std::env::var_os("SSH_AUTH_SOCK").map(PathBuf::from)
        } else {
            Some(expand_tilde(v))
        }
    };

    let proxy_command = {
        let v = first("proxycommand").trim();
        if v.is_empty() || v.eq_ignore_ascii_case("none") {
            None
        } else {
            Some(v.to_string())
        }
    };
    let proxy_jump = {
        let v = first("proxyjump").trim();
        if v.is_empty() || v.eq_ignore_ascii_case("none") {
            None
        } else {
            Some(v.to_string())
        }
    };

    // Server keepalive: 0 means disabled in OpenSSH, but russh benefits from
    // an active ping. Force 30s floor.
    let sai_raw: u64 = first("serveraliveinterval").parse().unwrap_or(0);
    let server_alive_interval = Duration::from_secs(sai_raw.max(30));
    let server_alive_count_max: u32 = first("serveralivecountmax").parse().unwrap_or(3);

    let strict_host_key_checking =
        match first("stricthostkeychecking").to_ascii_lowercase().as_str() {
            "yes" => StrictMode::Yes,
            "accept-new" => StrictMode::AcceptNew,
            "no" | "off" => StrictMode::No,
            _ => StrictMode::Ask,
        };

    let user_known_hosts_file = all("userknownhostsfile")
        .into_iter()
        .flat_map(|s| {
            s.split_whitespace()
                .map(expand_tilde)
                .collect::<Vec<_>>()
        })
        .collect();
    let global_known_hosts_file = all("globalknownhostsfile")
        .into_iter()
        .flat_map(|s| {
            s.split_whitespace()
                .map(expand_tilde)
                .collect::<Vec<_>>()
        })
        .collect();

    let host_key_algorithms = split_comma(first("hostkeyalgorithms"));
    let preferred_authentications = split_comma(first("preferredauthentications"));

    let compression = matches!(first("compression"), "yes" | "true");
    let hash_known_hosts = matches!(first("hashknownhosts"), "yes" | "true");

    Ok(ResolvedConfig {
        hostname,
        port,
        user,
        identity_files,
        identity_agent,
        proxy_command,
        proxy_jump,
        server_alive_interval,
        server_alive_count_max,
        strict_host_key_checking,
        user_known_hosts_file,
        global_known_hosts_file,
        host_key_algorithms,
        preferred_authentications,
        compression,
        hash_known_hosts,
    })
}

fn expand_tilde(p: &str) -> PathBuf {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            let mut pb = PathBuf::from(home);
            pb.push(rest);
            return pb;
        }
    }
    PathBuf::from(p)
}

fn split_comma(s: &str) -> Vec<String> {
    if s.is_empty() {
        return Vec::new();
    }
    s.split(',')
        .map(|t| t.trim().to_string())
        .filter(|t| !t.is_empty())
        .collect()
}

/// Shallow `~/.ssh/config` parser: extracts Host block names (no wildcards).
/// Used only to populate the sidebar "Remote Hosts" section — actual
/// per-host resolution goes through `resolve_host` (ssh -G).
///
/// Follows top-level `Include` directives (depth-limited to 5).
pub fn list_configured_hosts() -> Vec<String> {
    let Some(home) = std::env::var_os("HOME") else {
        return Vec::new();
    };
    let mut cfg_root = PathBuf::from(&home);
    cfg_root.push(".ssh/config");
    let mut seen = std::collections::HashSet::new();
    let mut buf = String::new();
    walk_includes(&cfg_root, 0, 5, &mut buf, &mut seen);
    parse_host_blocks(&buf)
}

pub fn parse_host_blocks(cfg: &str) -> Vec<String> {
    let mut out = Vec::new();
    for line in cfg.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let lower = trimmed.to_ascii_lowercase();
        // Only top-level `Host x y z` — skip `Match host …`
        if let Some(_rest) = lower.strip_prefix("host ") {
            // Use the original (non-lowered) slice for names
            let rest_orig = trimmed["Host".len()..].trim_start();
            for name in rest_orig.split_whitespace() {
                if !name.contains('*') && !name.contains('?') && !name.starts_with('!') {
                    out.push(name.to_string());
                }
            }
        }
    }
    out
}

fn walk_includes(
    path: &PathBuf,
    depth: u8,
    max_depth: u8,
    buf: &mut String,
    seen: &mut std::collections::HashSet<PathBuf>,
) {
    if depth >= max_depth {
        return;
    }
    let canon = match std::fs::canonicalize(path) {
        Ok(p) => p,
        Err(_) => return,
    };
    if !seen.insert(canon.clone()) {
        return;
    }
    let Ok(text) = std::fs::read_to_string(&canon) else {
        return;
    };
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed
            .strip_prefix("Include ")
            .or_else(|| trimmed.strip_prefix("include "))
        {
            for glob in rest.split_whitespace() {
                let expanded = expand_tilde(glob);
                // Very minimal glob: support trailing `*` in filename portion.
                if let Some(parent) = expanded.parent() {
                    if let Ok(entries) = std::fs::read_dir(parent) {
                        let fname = expanded
                            .file_name()
                            .map(|s| s.to_string_lossy().to_string())
                            .unwrap_or_default();
                        let is_star = fname.ends_with('*');
                        let prefix = fname.trim_end_matches('*').to_string();
                        for e in entries.flatten() {
                            let ep = e.path();
                            let n = ep
                                .file_name()
                                .map(|s| s.to_string_lossy().to_string())
                                .unwrap_or_default();
                            let matches =
                                if is_star { n.starts_with(&prefix) } else { n == fname };
                            if matches && ep.is_file() {
                                walk_includes(&ep, depth + 1, max_depth, buf, seen);
                            }
                        }
                    }
                } else if expanded.is_file() {
                    walk_includes(&expanded, depth + 1, max_depth, buf, seen);
                }
            }
        } else {
            buf.push_str(line);
            buf.push('\n');
        }
    }
}
