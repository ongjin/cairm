//! cairn-preview — minimal text preview with binary detection.
//!
//! Phase 1 surface:
//!   - `preview_text(path, max_bytes) -> Result<String, PreviewError>`
//!     • Reads up to 8 KB to decide binary vs text (NUL byte presence)
//!     • Text: reads up to `max_bytes`, appends `…(truncated)` if file was larger
//!     • Binary: returns `PreviewError::Binary` without reading further
//!
//! Syntax highlighting and large-file streaming are Phase 2.

use std::fs::File;
use std::io::{ErrorKind, Read};
use std::path::Path;
use thiserror::Error;

/// Sliding window used for binary detection. 8 KB covers the longest plausible
/// text-file prefix that might contain stray NULs (e.g., UTF-16 BOM + content).
const BINARY_SNIFF_BYTES: usize = 8 * 1024;

/// Suffix appended to the returned string when the file exceeded `max_bytes`.
pub const TRUNCATED_SUFFIX: &str = "\n…(truncated)";

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PreviewError {
    #[error("binary file")]
    Binary,
    #[error("not found")]
    NotFound,
    #[error("permission denied")]
    PermissionDenied,
    #[error("io error: {0}")]
    Io(String),
}

/// Reads up to `max_bytes` from `path`, returning either the text content or a
/// classified error. Binary detection uses the first 8 KB — a file is binary if
/// any byte in that window is 0x00 or the slice is not valid UTF-8.
pub fn preview_text(path: &Path, max_bytes: usize) -> Result<String, PreviewError> {
    // max_bytes == 0 is a degenerate request (caller explicitly asked for zero
    // content). Return empty without reading — avoids surprising binary-classify
    // behavior when the sniff buffer would be zero-length.
    if max_bytes == 0 {
        return Ok(String::new());
    }
    let mut file = File::open(path).map_err(io_classify)?;

    // First 8 KB: sniff NUL + validate UTF-8.
    let sniff_cap = BINARY_SNIFF_BYTES.min(max_bytes);
    let mut sniff = vec![0u8; sniff_cap];
    let n = read_up_to(&mut file, &mut sniff).map_err(io_classify)?;
    sniff.truncate(n);

    if sniff.iter().any(|&b| b == 0) {
        return Err(PreviewError::Binary);
    }
    if std::str::from_utf8(&sniff).is_err() {
        return Err(PreviewError::Binary);
    }

    // Text path — keep reading until max_bytes or EOF.
    let mut out = sniff;
    let remaining = max_bytes.saturating_sub(out.len());
    if remaining > 0 {
        let mut tail = vec![0u8; remaining];
        let t = read_up_to(&mut file, &mut tail).map_err(io_classify)?;
        tail.truncate(t);
        // Re-validate UTF-8 once concatenated — the boundary we read at might
        // have split a multi-byte codepoint.
        out.extend_from_slice(&tail);
        if std::str::from_utf8(&out).is_err() {
            return Err(PreviewError::Binary);
        }
    }

    // Detect truncation by attempting one more byte read.
    let mut peek = [0u8; 1];
    let more = file.read(&mut peek).map_err(io_classify)?;
    let mut s = String::from_utf8(out).expect("utf-8 validated above");
    if more > 0 {
        s.push_str(TRUNCATED_SUFFIX);
    }
    Ok(s)
}

fn read_up_to<R: Read>(r: &mut R, buf: &mut [u8]) -> std::io::Result<usize> {
    let mut filled = 0;
    while filled < buf.len() {
        match r.read(&mut buf[filled..]) {
            Ok(0) => break,
            Ok(n) => filled += n,
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(filled)
}

fn io_classify(err: std::io::Error) -> PreviewError {
    match err.kind() {
        ErrorKind::NotFound => PreviewError::NotFound,
        ErrorKind::PermissionDenied => PreviewError::PermissionDenied,
        _ => PreviewError::Io(err.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn write_tmp(bytes: &[u8]) -> NamedTempFile {
        let mut f = NamedTempFile::new().expect("tempfile");
        f.write_all(bytes).expect("write");
        f.flush().expect("flush");
        f
    }

    #[test]
    fn text_under_max_bytes_returned_as_is() {
        let tmp = write_tmp(b"hello world");
        let out = preview_text(tmp.path(), 1024).unwrap();
        assert_eq!(out, "hello world");
    }

    #[test]
    fn text_over_max_bytes_is_truncated_with_suffix() {
        let tmp = write_tmp(b"abcdefghij");
        let out = preview_text(tmp.path(), 4).unwrap();
        // first 4 bytes + truncation suffix.
        assert!(out.starts_with("abcd"));
        assert!(out.ends_with(TRUNCATED_SUFFIX));
    }

    #[test]
    fn nul_byte_in_sniff_window_is_binary() {
        let mut bytes = b"some text".to_vec();
        bytes.push(0u8);
        bytes.extend_from_slice(b"more");
        let tmp = write_tmp(&bytes);
        assert_eq!(preview_text(tmp.path(), 1024), Err(PreviewError::Binary));
    }

    #[test]
    fn invalid_utf8_prefix_is_binary() {
        // 0xC0 0xC0 is an illegal UTF-8 lead-byte pair.
        let tmp = write_tmp(&[0xC0u8, 0xC0u8, 0xC0u8]);
        assert_eq!(preview_text(tmp.path(), 1024), Err(PreviewError::Binary));
    }

    #[test]
    fn not_found_maps_to_not_found_error() {
        let ghost = std::path::PathBuf::from("/tmp/cairn-preview-test-does-not-exist-zzzz");
        assert_eq!(preview_text(&ghost, 1024), Err(PreviewError::NotFound));
    }

    #[test]
    fn multibyte_utf8_across_max_boundary_classifies_as_binary() {
        // 한글 '가' = 0xEA 0xB0 0x80. If max_bytes slices inside it AND the remainder
        // isn't read, the output can't be valid UTF-8.
        let tmp = write_tmp("가나다".as_bytes()); // 9 bytes total
                                                  // max_bytes = 2: we read 2 bytes of the first 3-byte codepoint, so the
                                                  // assembled buffer is invalid UTF-8 → Binary. This is acceptable behavior
                                                  // for Phase 1; Phase 2 may refine to respect codepoint boundaries.
        assert_eq!(preview_text(tmp.path(), 2), Err(PreviewError::Binary));
    }
}
