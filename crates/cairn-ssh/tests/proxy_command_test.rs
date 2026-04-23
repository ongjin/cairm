use cairn_ssh::proxy::dial_with_proxy;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn proxy_command_echoes_stdio() {
    // Use `cat` as a trivial proxy that echoes stdin to stdout.
    let mut stream = dial_with_proxy("cat", "ignored", 0, "ignored").await.unwrap();
    stream.write_all(b"hello\n").await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = [0u8; 6];
    stream.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"hello\n");
}

#[tokio::test]
async fn proxy_command_spawn_failure_surfaces() {
    let err = dial_with_proxy("/nonexistent-binary-xyz-cairn-test", "h", 22, "u").await;
    assert!(err.is_err());
}

#[tokio::test]
async fn proxy_command_token_expansion() {
    // `echo %h %p %r` → subshell prints the expanded arguments.
    let mut stream = dial_with_proxy("echo %h %p %r", "prod-api", 2222, "deploy").await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    assert_eq!(String::from_utf8_lossy(&buf).trim(), "prod-api 2222 deploy");
}
