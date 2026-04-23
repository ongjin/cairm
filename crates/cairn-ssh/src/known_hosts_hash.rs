use base64::prelude::*;
use hmac::{Hmac, Mac};
use sha1::Sha1;

type HmacSha1 = Hmac<Sha1>;

/// Match an OpenSSH hashed known_hosts token (format `|1|<b64 salt>|<b64 hmac>`)
/// against a host name.
pub fn match_hashed_entry(token: &str, host: &str) -> bool {
    let rest = match token.strip_prefix("|1|") {
        Some(r) => r,
        None => return false,
    };
    let mut parts = rest.splitn(2, '|');
    let (salt_b64, mac_b64) = match (parts.next(), parts.next()) {
        (Some(s), Some(m)) => (s, m),
        _ => return false,
    };
    let salt = match BASE64_STANDARD.decode(salt_b64) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let expected = match BASE64_STANDARD.decode(mac_b64) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let mut mac = match HmacSha1::new_from_slice(&salt) {
        Ok(m) => m,
        Err(_) => return false,
    };
    mac.update(host.as_bytes());
    mac.verify_slice(&expected).is_ok()
}
