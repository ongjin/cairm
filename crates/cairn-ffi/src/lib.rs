//! cairn-ffi — the only crate the Swift app sees.
//!
//! Defines swift-bridge modules that expose Rust functions as Swift APIs.
//! Phase 0 exposes a single `greet()` to prove the pipeline.

#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        fn greet() -> String;
    }
}

fn greet() -> String {
    format!("{} (from Rust)", cairn_core::hello())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_wraps_core_hello() {
        assert_eq!(greet(), "Hello, Cairn! (from Rust)");
    }
}
