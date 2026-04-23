#![cfg(feature = "integration")]

pub fn skip_unless_env() {
    if std::env::var("CAIRN_SSH_IT").ok().as_deref() != Some("1") {
        println!("skip: set CAIRN_SSH_IT=1 to run");
        std::process::exit(0);
    }
}
