use cairn_ssh::config::{parse_host_blocks, parse_ssh_g_output};

#[test]
fn parse_simple_ssh_g() {
    let out = "\
hostname 10.0.1.5
port 22
user deploy
identityfile ~/.ssh/id_ed25519
serveraliveinterval 60
serveralivecountmax 3
stricthostkeychecking ask
userknownhostsfile ~/.ssh/known_hosts
hashknownhosts no
compression no
";
    let cfg = parse_ssh_g_output(out).unwrap();
    assert_eq!(cfg.hostname, "10.0.1.5");
    assert_eq!(cfg.port, 22);
    assert_eq!(cfg.user, "deploy");
    assert_eq!(cfg.server_alive_interval.as_secs(), 60);
    assert!(!cfg.hash_known_hosts);
    // ~/ should expand to absolute path
    assert!(cfg.identity_files[0].starts_with(std::env::var_os("HOME").unwrap()));
}

#[test]
fn parse_proxy_command() {
    let out = "\
hostname prod-internal
port 22
user deploy
proxycommand cloudflared access ssh --hostname %h
";
    let cfg = parse_ssh_g_output(out).unwrap();
    assert_eq!(
        cfg.proxy_command.as_deref(),
        Some("cloudflared access ssh --hostname %h")
    );
}

#[test]
fn parse_default_fills_in() {
    // Empty output — parser should fill defaults
    let cfg = parse_ssh_g_output("hostname localhost\n").unwrap();
    assert_eq!(cfg.port, 22);
    assert_eq!(cfg.server_alive_interval.as_secs(), 30); // 0 → 30 bump
    assert_eq!(cfg.user, std::env::var("USER").unwrap_or_default());
}

#[test]
fn host_blocks_list_skips_wildcards() {
    let cfg = "\
Host prod-api staging-db
    HostName 10.0.1.5

Host *.internal
    User deploy

Host git-*
    IdentityFile ~/.ssh/git_key

Host dev-tunnel
    ProxyCommand cloudflared access ssh --hostname %h
";
    let hosts = parse_host_blocks(cfg);
    assert_eq!(hosts, vec!["prod-api", "staging-db", "dev-tunnel"]);
}
