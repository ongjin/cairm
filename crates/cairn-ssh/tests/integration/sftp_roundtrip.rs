#![cfg(feature = "integration")]

// Requires a running openssh-server at localhost:2222 with user 'test' and
// a password-less key from tests/fixtures/test_ed25519 in authorized_keys.
//
// Quick start:
//   docker run -d --name cairn-ssh-it -p 2222:22 \
//     -v $(pwd)/tests/fixtures/authorized_keys:/home/test/.ssh/authorized_keys:ro \
//     linuxserver/openssh-server
//
// Run:
//   CAIRN_SSH_IT=1 cargo test -p cairn-ssh --features integration --test sftp_roundtrip

#[tokio::test]
async fn upload_download_roundtrip() {
    super::skip_unless_env();
    // TODO: instantiate SshPool, connect to localhost:2222, upload a temp file,
    // download it back, assert byte equality, delete remote file.
    // Blocked on plumbing real hostkey/passphrase resolvers for the test env.
    // See tests/fixtures/ for the planned key material location.
    todo!("implement after Docker fixture is set up")
}
