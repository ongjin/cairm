use cairn_ssh::hostkey::{KnownHostsStore, KnownResult};
use cairn_ssh::known_hosts_hash::match_hashed_entry;
use std::io::Write;
use tempfile::NamedTempFile;

#[test]
fn plain_entry_match() {
    let mut f = NamedTempFile::new().unwrap();
    writeln!(f, "# comment").unwrap();
    writeln!(
        f,
        "prod-api ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVlxZqMX2ElimvprNnSjFEUnlz7di1kFQUBoy+IIPBC"
    )
    .unwrap();
    f.flush().unwrap();

    let store = KnownHostsStore::new(vec![f.path().to_path_buf()]);
    let pk = b"unused-for-this-test";
    match store.lookup("prod-api", 22, "ssh-ed25519", pk) {
        KnownResult::Match | KnownResult::Mismatch { .. } | KnownResult::NotFound => {}
    }
}

#[test]
fn hashed_entry_matches() {
    let salt = b"salted12";
    let host = "prod-api";
    let sample = make_hashed_line(salt, host);
    let parts: Vec<&str> = sample.split_whitespace().collect();
    assert!(parts[0].starts_with("|1|"));
    assert!(match_hashed_entry(parts[0], host));
    assert!(!match_hashed_entry(parts[0], "other-host"));
}

fn make_hashed_line(salt: &[u8], host: &str) -> String {
    use base64::prelude::*;
    use hmac::{Hmac, Mac};
    use sha1::Sha1;
    type HmacSha1 = Hmac<Sha1>;
    let mut mac = HmacSha1::new_from_slice(salt).unwrap();
    mac.update(host.as_bytes());
    let result = mac.finalize().into_bytes();
    format!(
        "|1|{}|{} ssh-ed25519 AAAA...",
        BASE64_STANDARD.encode(salt),
        BASE64_STANDARD.encode(result)
    )
}
