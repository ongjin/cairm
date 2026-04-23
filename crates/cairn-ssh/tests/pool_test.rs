use cairn_ssh::types::ConnKey;

#[test]
fn connkey_dedup_by_content() {
    use cairn_ssh::types::{ResolvedConfig, StrictMode};
    use std::time::Duration;
    let base = ResolvedConfig {
        hostname: "h".into(),
        port: 22,
        user: "u".into(),
        identity_files: vec!["/k".into()],
        identity_agent: None,
        proxy_command: None,
        proxy_jump: None,
        server_alive_interval: Duration::from_secs(30),
        server_alive_count_max: 3,
        strict_host_key_checking: StrictMode::Ask,
        user_known_hosts_file: vec![],
        global_known_hosts_file: vec![],
        host_key_algorithms: vec![],
        preferred_authentications: vec![],
        compression: false,
        hash_known_hosts: false,
        password: None,
    };
    let a = ConnKey::from_resolved(&base);
    let b = ConnKey::from_resolved(&base);
    assert_eq!(a, b);

    let mut base2 = base.clone();
    base2.proxy_command = Some("cloudflared access ssh --hostname %h".into());
    let c = ConnKey::from_resolved(&base2);
    assert_ne!(a, c);
}
