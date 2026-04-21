use std::path::PathBuf;

fn main() {
    // swift-bridge-build이 src/lib.rs의 #[swift_bridge::bridge] 모듈을 파싱해
    // ./generated/ 아래에 Swift 소스와 C 헤더를 생성한다.
    let out_dir = PathBuf::from("./generated");

    let bridges = vec!["src/lib.rs"];
    for path in &bridges {
        println!("cargo:rerun-if-changed={}", path);
    }

    swift_bridge_build::parse_bridges(bridges)
        .write_all_concatenated(out_dir, "cairn_ffi");
}
