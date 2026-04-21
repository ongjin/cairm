//! cairn-core — public façade for the Cairn engine.
//!
//! In Phase 0, this is a skeleton that exposes `hello()` used to prove
//! the FFI pipeline. Real engine APIs land in Phase 1+.

pub fn hello() -> String {
    "Hello, Cairn!".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_returns_expected_greeting() {
        assert_eq!(hello(), "Hello, Cairn!");
    }
}
