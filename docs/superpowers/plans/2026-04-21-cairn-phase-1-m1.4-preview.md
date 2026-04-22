# Cairn Phase 1 · M1.4 — Preview Pane + `Space` Quick Look + `⌘⇧.` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1.3 의 `previewPlaceholder` 를 **실제 프리뷰 패널** 로 교체한다. Rust `cairn-preview` 크레이트 신설 (`preview_text` — 첫 8KB NUL 검사로 binary 판정, text 는 `max_bytes` 까지 반환), Swift `PreviewModel` (LRU 16 캐시), `PreviewPaneView` 5-way 라우팅 (text / image / directory / binary / failed), `Space` 로 QLPreviewPanel, `⌘⇧.` 로 숨김 파일 토글. 디자인 폴리싱은 M1.5.

**Architecture:**
- **Rust layer** — `cairn-preview::preview_text(path, max_bytes) -> Result<String, PreviewError>` 단일 함수. Binary 판정은 첫 8KB 에서 `\0` 바이트 찾기. UTF-8 변환 실패 시에도 `Binary` 리턴 (lossy 회피). `cairn-core::Engine::preview_text` 가 이를 re-export. `cairn-ffi` 가 `PreviewError` + `engine.preview_text(path)` 를 Swift 로 노출.
- **Swift data layer** — `CairnEngine.previewText(_:) async throws -> String` (기존 `listDirectory` 와 같은 Task.detached 패턴). `PreviewModel` 은 `@Observable`, `var focus: URL?` / `var state: PreviewState` 노출. LRU `[URL: PreviewState]` 16 엔트리. `focus` 는 `FolderModel.selection` 첫 항목을 `ContentView.onChange` 가 설정.
- **Swift view layer** — `PreviewPaneView` 가 `PreviewState` 에 따라 `TextPreview` / `ImagePreview` / `DirectoryPreview` / `BinaryPreview` / `FailedPreview` / `IdlePreview` 중 하나를 그림. `ImagePreview` 는 `NSImage(contentsOf:)` off-main + 256pt 스케일. 각 렌더러는 파일별 메타 (크기, 수정 시각, 확장자) 도 함께 표시.
- **Quick Look (`Space`)** — `FileListNSTableView.keyDown` 에 keyCode 49 추가. `QLPreviewPanel.shared().makeKeyAndOrderFront(nil)` 호출. `FileListCoordinator` 가 `QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` 구현, `FileListNSTableView` 의 `-acceptsPreviewPanelControl(_:)` / `-beginPreviewPanelControl(_:)` 오버라이드로 Coordinator 를 delegate 로 등록. 선택된 행이 여러 개면 QLPanel 이 그 목록을 순회.
- **`⌘⇧.` hidden toggle** — ContentView toolbar 에 invisible button (또는 .commands menu) 에 `.keyboardShortcut(".", modifiers: [.command, .shift])` 바인딩. `app.toggleShowHidden()` 후 현재 폴더 `folder?.load(url)` 재호출로 리스트 리로드.

**Tech Stack:** Rust 1.85 · Swift 5.9 · swift-bridge 0.1.59 · SwiftUI · AppKit (`QLPreviewPanel`, `NSImage`) · `@Observable` · macOS 14+ · `anyhow`/`thiserror` (cairn-preview)

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, HEAD 시작은 `phase-1-m1.3` 태그)

**Predecessor:** M1.3 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.3-sidebar-landing.md` (완료)
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` § 4.2 / § 11 M1.4

**Deliverable verification (M1.4 완료 조건):**
- `cargo test --workspace` 녹색 — `cairn-preview` 신규 ≥ 5 테스트 + `cairn-core::preview_text` 합류
- `xcodebuild build` 성공
- `xcodebuild test` 녹색 — `PreviewModelTests` ≥ 3 추가 → 기존 17 + 3 = 20
- 앱 실행 → 파일 행 선택 시 detail 패널에 프리뷰 렌더 (텍스트 monospace, 이미지 썸네일, 바이너리 "미리보기 불가", 폴더는 "N items", 파일 선택 해제 시 idle)
- `Space` → QLPreviewPanel 표시, `Esc` / `Space` 로 닫힘
- `⌘⇧.` → 숨김 파일 보이기/숨기기 즉시 반영
- 여러 파일 선택 시 첫 번째 기준으로 프리뷰
- `git tag phase-1-m1.4` 로 기준점

---

## 1. 기술 참조 (M1.4 특유 함정)

- **swift-bridge 0.1.59 의 `Result<String, E>`** — Phase 1 에서 `Result<FileListing, WalkerError>` 은 opaque 타입으로 우회했지만, `String` 은 swift-bridge 가 transparent 로 취급. `Result<String, PreviewError>` 는 **바로 된다** (엔트리 문서 기준). 만약 codegen panic 나면 `Option<String>` + 별도 `last_error() -> PreviewError` 패턴으로 폴백.
- **swift-bridge `Error` conformance** — `PreviewError` 도 `WalkerError` 처럼 Swift 쪽에서 자동으로 `Error` 를 만족 안 함. `apps/Sources/Services/CairnEngine.swift` 에 `extension PreviewError: Error {}` 를 추가.
- **Binary 판정** — 첫 8KB 에서 `\0` 바이트를 찾는 단순 규칙. PDF / ZIP / 이미지 모두 첫 8KB 에 NUL 이 있음. 예외: CR/LF 만 있는 ASCII 텍스트는 NUL 없음 → text 판정. UTF-16 BOM (`\xFF\xFE` or `\xFE\xFF`) 은 NUL 이 많으므로 자동으로 binary 판정 — 의도한 동작 (Phase 1 은 UTF-8 만 지원).
- **`QLPreviewPanel` responder chain** — SwiftUI window 에선 `NSView` 가 first responder 가 돼야 panel control 이 발동. `FileListNSTableView` 가 `-acceptsPreviewPanelControl(_:)` 을 오버라이드하지 않으면 panel 이 뜨지만 내용은 empty. **오버라이드 필수.**
- **`URL` vs `NSURL` as `QLPreviewItem`** — `NSURL: QLPreviewItem` 은 OS 내장. Swift `URL` 은 직접 conform 안 함. 캐스트 시 `url as NSURL` 로 전달.
- **`⌘⇧.` keyboard shortcut 커버리지** — `KeyboardShortcut(".", modifiers: [.command, .shift])` 로 확실히 동작. 일부 유저 키보드 레이아웃에서 `.` 의 keyEquivalent 가 달라질 수 있으나 macOS 표준 US / 한글 입력기에서는 `.` 로 통일.
- **`NSImage(contentsOf:)` 메인 스레드** — `NSImage` 는 lazy decode 라 init 자체는 빠르지만 대형 이미지의 경우 display 시 main thread stall. `Task.detached` 로 init + `preferredSize` 계산까지 수행, 디코딩된 이미지를 main 에서 SwiftUI `Image(nsImage:)` 로 전달.
- **`FolderModel.selection` 은 `Set<String>`** — 선택 여러 개일 때 순서가 없다. 프리뷰 "첫 항목" 을 정하려면 `lastSnapshot` 의 row 순서를 기준 삼아야 하는데 PreviewModel 은 snapshot 몰라도 된다. **대신**: Coordinator 가 selection 변경 시 `lastSnapshot` 안에서 첫 selected row 의 path 를 뽑아 closure 로 PreviewModel 에 넘긴다. Set 만 들고 뒤늦게 "첫 항목" 찾으려 하면 비결정적.
- **`⌘R` reload** — 스펙 § 8 에 있지만 M1.4 필수 아님. `⌘⇧.` 가 사실상 reload 를 강제하므로 명시적 `⌘R` 은 M1.6 cleanup 에서 추가.

---

## 2. File Structure

**Rust (crates/):**
- Modify: `crates/cairn-preview/Cargo.toml` (workspace deps 추가)
- Modify: `crates/cairn-preview/src/lib.rs` (skeleton 교체 — `preview_text` 구현)
- Modify: `crates/cairn-core/Cargo.toml` (cairn-preview dep 추가)
- Modify: `crates/cairn-core/src/lib.rs` (`Engine::preview_text` 추가)
- Modify: `crates/cairn-ffi/Cargo.toml` (cairn-preview dep 추가)
- Modify: `crates/cairn-ffi/src/lib.rs` (PreviewError bridging + `engine.preview_text`)

**Swift (apps/Sources/):**
- Modify: `apps/Sources/Services/CairnEngine.swift` (`extension PreviewError: Error {}` + `previewText(_:)`)
- Create: `apps/Sources/ViewModels/PreviewModel.swift` (focus + state + LRU cache)
- Create: `apps/Sources/Views/Preview/PreviewPaneView.swift` (state → renderer 라우팅)
- Create: `apps/Sources/Views/Preview/PreviewRenderers.swift` (TextPreview / ImagePreview / DirectoryPreview / BinaryPreview / FailedPreview / IdlePreview)
- Modify: `apps/Sources/ContentView.swift` (`previewPlaceholder` → `PreviewPaneView`, `⌘⇧.` shortcut, selection → preview focus wiring)
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift` (`QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` 구현, selection 변경 시 first-selected path 콜백 `onSelectionChanged`)
- Modify: `apps/Sources/Views/FileList/FileListNSTableView.swift` (keyCode 49 = Space → QLPanel, `-acceptsPreviewPanelControl/-begin/-endPreviewPanelControl` 오버라이드)
- Modify: `apps/Sources/Views/FileList/FileListView.swift` (`onSelectionChanged` 파라미터 추가)
- Modify: `apps/Sources/App/AppModel.swift` (`previewModel: PreviewModel` 주입)

**Swift tests (apps/CairnTests/):**
- Create: `apps/CairnTests/PreviewModelTests.swift` (focus / LRU cache / state transitions)

---

## Task 1: `cairn-preview` — `preview_text` + `PreviewError` (TDD)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-preview/Cargo.toml`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-preview/src/lib.rs`

첫 8KB NUL 검사 + `max_bytes` 까지 UTF-8 읽기. 실패 분류는 `PreviewError`.

- [ ] **Step 1: `Cargo.toml` 에 의존성 추가**

기존 `crates/cairn-preview/Cargo.toml` 을 다음으로 교체:

```toml
[package]
name = "cairn-preview"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_preview"

[dependencies]
thiserror = { workspace = true }

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: `src/lib.rs` 교체 — 구현 + 단위 테스트**

`crates/cairn-preview/src/lib.rs` 를 다음으로 교체:

```rust
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
```

- [ ] **Step 3: 테스트 실행 — 6/6 통과**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-preview 2>&1 | tail -15
```

Expected: `test result: ok. 6 passed; 0 failed`.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-preview/Cargo.toml crates/cairn-preview/src/lib.rs
git commit -m "feat(cairn-preview): add preview_text with binary detection + truncation"
```

---

## Task 2: `cairn-core::Engine::preview_text` — re-export wiring

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-core/Cargo.toml`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-core/src/lib.rs`

- [ ] **Step 1: `cairn-core/Cargo.toml` 에 dep 추가**

파일 상단의 기존 `[dependencies]` 섹션 찾아 `cairn-preview` 줄 추가. 파일이 어떻게 생겼는지 모르면 전체 열어보고 기존 walker dep 옆에 추가:

```bash
cd /Users/cyj/workspace/personal/cairn
cat crates/cairn-core/Cargo.toml
```

기존 내용을 유지하면서, `[dependencies]` 섹션에 다음 줄 추가:

```toml
cairn-preview = { path = "../cairn-preview" }
```

(이미 `cairn-walker = { path = "../cairn-walker" }` 가 있을 테니 그 바로 아래.)

- [ ] **Step 2: `cairn-core/src/lib.rs` 수정**

기존 `src/lib.rs` 상단의 `use cairn_walker::...` 라인 다음에 추가:

```rust
pub use cairn_preview::PreviewError;
```

그리고 `impl Engine { ... }` 블록 안 `pub fn set_show_hidden` 바로 위에 다음 메서드 추가:

```rust
    pub fn preview_text(&self, path: &Path) -> Result<String, PreviewError> {
        // 64 KB — balances "enough to see code context" vs "snappy".
        // Phase 2 will make this configurable + stream-based.
        cairn_preview::preview_text(path, 64 * 1024)
    }
```

- [ ] **Step 3: cargo test — 통과**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-core 2>&1 | tail -5
```

Expected: 기존 테스트 + 새 것 모두 통과. (새 테스트 안 추가 — preview_text 는 cairn-preview 에서 이미 검증됨, core 에선 re-export 만.)

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-core/Cargo.toml crates/cairn-core/src/lib.rs
git commit -m "feat(cairn-core): re-export PreviewError + Engine::preview_text"
```

---

## Task 3: `cairn-ffi` — PreviewError bridging + `engine.preview_text`

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-ffi/Cargo.toml`
- Modify: `/Users/cyj/workspace/personal/cairn/crates/cairn-ffi/src/lib.rs`

swift-bridge 의 `Result<String, PreviewError>` 는 String 이 transparent 이므로 opaque 우회 없이 바로 적용 가능 (Walker 는 Vec<Struct> 때문에 우회 필요했음).

- [ ] **Step 1: `cairn-ffi/Cargo.toml` 에 dep 추가**

기존 `[dependencies]` 섹션에 추가:

```toml
cairn-preview = { path = "../cairn-preview" }
```

- [ ] **Step 2: `cairn-ffi/src/lib.rs` 수정**

`ffi` 모듈의 `enum WalkerError { ... }` 블록 바로 아래에 다음 enum 추가:

```rust
    enum PreviewError {
        Binary,
        NotFound,
        PermissionDenied,
        Io(String),
    }
```

그 바로 아래, 첫 `extern "Rust"` 블록 (Engine 관련) 의 `fn set_show_hidden(&mut self, show: bool);` 다음 줄에 추가:

```rust
        fn preview_text(&self, path: String) -> Result<String, PreviewError>;
```

그리고 `impl Engine { ... }` 블록 안, `fn set_show_hidden` 바로 위에 다음 메서드 추가:

```rust
    fn preview_text(&self, path: String) -> Result<String, ffi::PreviewError> {
        self.inner
            .preview_text(Path::new(&path))
            .map_err(wire_preview_error)
    }
```

파일 하단, `fn wire_walker_error` 다음에 다음 변환 함수 추가:

```rust
fn wire_preview_error(e: cairn_core::PreviewError) -> ffi::PreviewError {
    use cairn_core::PreviewError as P;
    match e {
        P::Binary => ffi::PreviewError::Binary,
        P::NotFound => ffi::PreviewError::NotFound,
        P::PermissionDenied => ffi::PreviewError::PermissionDenied,
        P::Io(msg) => ffi::PreviewError::Io(msg),
    }
}
```

`#[cfg(test)] mod tests` 내부에 smoke 테스트 하나 추가 (파일 끝의 `file_listing_entry_matches_length` 테스트 다음):

```rust
    #[test]
    fn engine_preview_text_on_cargo_toml_roundtrips() {
        let engine = new_engine();
        // This crate's own Cargo.toml is always present and small.
        let path = env!("CARGO_MANIFEST_DIR").to_string() + "/Cargo.toml";
        match engine.preview_text(path) {
            Ok(s) => assert!(s.contains("cairn-ffi")),
            Err(_) => panic!("preview_text failed on Cargo.toml"),
        }
    }
```

- [ ] **Step 3: cargo test + build-rust.sh + gen-bindings.sh**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-ffi 2>&1 | tail -5
./scripts/build-rust.sh 2>&1 | tail -3
./scripts/gen-bindings.sh 2>&1 | tail -5
```

Expected:
- cargo test: 기존 smoke + 새 smoke = 3 통과
- build-rust: universal lib 빌드 성공
- gen-bindings: 4 파일 copy, **이 때 Swift 쪽 `Generated/cairn_ffi.swift` 에 `PreviewError` 타입이 자동 생성돼야 함** — 없으면 swift-bridge codegen 이 panic 하거나 silent 로 skip 한 것. 생성 파일 확인:

```bash
grep -n "PreviewError" /Users/cyj/workspace/personal/cairn/apps/Sources/Generated/cairn_ffi.swift | head -5
```

`PreviewError` 관련 줄이 몇 개 떠야 한다. 없으면 STOP 하고 swift-bridge codegen 로그 재확인.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add crates/cairn-ffi/Cargo.toml crates/cairn-ffi/src/lib.rs apps/Sources/Generated
git commit -m "feat(cairn-ffi): bridge PreviewError + engine.preview_text to Swift"
```

---

## Task 4: Swift `CairnEngine.previewText(_:)` async wrapper

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Services/CairnEngine.swift`

`listDirectory` 와 같은 `Task.detached` 패턴. 맨 위 `extension WalkerError: Error {}` 옆에 `extension PreviewError: Error {}` 도 추가.

- [ ] **Step 1: 파일 상단 extension 추가**

`apps/Sources/Services/CairnEngine.swift` 상단의 기존 한 줄:

```swift
extension WalkerError: Error {}
```

다음으로 교체 (두 줄):

```swift
extension WalkerError: Error {}
extension PreviewError: Error {}
```

- [ ] **Step 2: `CairnEngine` 클래스 안에 `previewText` 추가**

클래스의 마지막 메서드 `setShowHidden(_:)` 바로 위에 다음을 삽입:

```swift
    /// Returns up to 64 KB of decoded text content from `url`. Throws
    /// `PreviewError.Binary` on binary detection, `.NotFound`/`.PermissionDenied`
    /// on file-system errors. Caller is responsible for scoped access.
    func previewText(_ url: URL) async throws -> String {
        let path = url.path
        return try await Task.detached { [rust] in
            try rust.preview_text(path)
        }.value
    }
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 빌드 실패 시 `PreviewError` 타입 이름이 Generated bindings 와 맞는지 확인.

- [ ] **Step 4: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 17/17 여전히 통과.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Services/CairnEngine.swift
git commit -m "feat(cairn-engine): add previewText async wrapper + PreviewError: Error"
```

---

## Task 5: `PreviewModel` — focus + state + LRU (TDD)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/ViewModels/PreviewModel.swift`
- Create: `/Users/cyj/workspace/personal/cairn/apps/CairnTests/PreviewModelTests.swift`

`PreviewModel` 은 현재 focus URL + 해당 URL 의 상태 (text / binary / 등) 를 소유. LRU 캐시 16 엔트리. UI 는 `state` 만 관찰.

- [ ] **Step 1: `PreviewModelTests.swift` — 실패 테스트 작성**

```swift
import XCTest
@testable import Cairn

final class PreviewModelTests: XCTestCase {
    func test_initial_state_is_idle() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        if case .idle = model.state {} else { XCTFail("initial state should be .idle") }
        XCTAssertNil(model.focus)
    }

    func test_focus_nil_clears_state_to_idle() async {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Preload a focused URL → directory case.
        model.focus = FileManager.default.temporaryDirectory
        model.state = .directory(childCount: 5)
        model.focus = nil
        if case .idle = model.state {} else { XCTFail("nil focus should reset to .idle") }
    }

    func test_lru_caches_up_to_16_then_evicts_oldest() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Inject 17 arbitrary cached URLs — the first one should be evicted.
        for i in 0..<17 {
            let u = URL(fileURLWithPath: "/tmp/preview-\(i)")
            model.cache(state: .text("content-\(i)"), for: u)
        }
        XCTAssertNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-0")),
                     "oldest entry should have been evicted")
        XCTAssertNotNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-16")),
                        "newest entry should be present")
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -10
```

Expected: `Cannot find 'PreviewModel'`.

- [ ] **Step 3: `PreviewModel.swift` 작성**

```swift
import Foundation
import Observation

/// Preview state for the currently-focused URL. Owned by PreviewModel; read by
/// PreviewPaneView to pick the right renderer.
enum PreviewState: Equatable {
    case idle                       // no focus
    case loading                    // fetch in-flight
    case text(String)               // decoded text body (possibly truncated)
    case image(path: String)        // NSImage loaded lazily by the renderer
    case directory(childCount: Int) // summary for a selected folder
    case binary                     // binary / unsupported
    case failed(String)             // user-facing error string
}

/// Drives the detail pane.
///
/// `focus` is the URL the user currently wants previewed (driven by selection
/// in the file list). Setting `focus` kicks off an async fetch via the engine
/// and caches the result in an LRU (16 entries) so back-forth selection is
/// instant after the first visit.
@Observable
final class PreviewModel {
    static let cacheCapacity = 16

    var focus: URL? {
        didSet { handleFocusChange(from: oldValue) }
    }
    var state: PreviewState = .idle

    private let engine: CairnEngine

    /// Insertion-ordered (oldest → newest) for cheap LRU eviction.
    /// Keyed on standardizedFileURL.path so duplicate URL forms alias.
    private var cacheKeys: [String] = []
    private var cacheValues: [String: PreviewState] = [:]

    init(engine: CairnEngine) {
        self.engine = engine
    }

    // MARK: - Cache

    /// Test/internal helper — directly poke a value into the cache without
    /// invoking the engine. Production callers set `focus` instead.
    func cache(state: PreviewState, for url: URL) {
        let key = url.standardizedFileURL.path
        if cacheValues[key] != nil {
            cacheKeys.removeAll { $0 == key }
        }
        cacheKeys.append(key)
        cacheValues[key] = state
        evictIfNeeded()
    }

    func cached(for url: URL) -> PreviewState? {
        cacheValues[url.standardizedFileURL.path]
    }

    private func evictIfNeeded() {
        while cacheKeys.count > Self.cacheCapacity {
            let dropped = cacheKeys.removeFirst()
            cacheValues.removeValue(forKey: dropped)
        }
    }

    // MARK: - Focus handling

    private func handleFocusChange(from previous: URL?) {
        guard let focus else {
            state = .idle
            return
        }
        if let hit = cached(for: focus) {
            state = hit
            return
        }
        state = .loading
        Task { [weak self] in
            await self?.loadPreview(for: focus)
        }
    }

    @MainActor
    private func loadPreview(for url: URL) async {
        let next = await Self.compute(for: url, engine: engine)
        cache(state: next, for: url)
        // Only publish if the focus is still the same URL (user might have
        // selected something else while we were awaiting).
        if focus == url {
            state = next
        }
    }

    /// Decide which preview branch applies. Directories and images are decided
    /// by path inspection; text vs binary is decided by `preview_text`.
    private static func compute(for url: URL, engine: CairnEngine) async -> PreviewState {
        let path = url.standardizedFileURL.path

        // Directory?
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return .directory(childCount: children.count)
        }

        // Image?
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            return .image(path: path)
        }

        // Text via Rust.
        do {
            let body = try await engine.previewText(url)
            return .text(body)
        } catch let e as PreviewError {
            switch e {
            case .Binary: return .binary
            case .NotFound: return .failed("File not found.")
            case .PermissionDenied: return .failed("Permission denied.")
            case .Io(let msg): return .failed("I/O error: \(msg.toString())")
            }
        } catch {
            return .failed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: 테스트 재실행 — 3/3 통과**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20 (기존 17 + PreviewModel 3).

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ViewModels/PreviewModel.swift apps/CairnTests/PreviewModelTests.swift
git commit -m "feat(preview-model): add PreviewModel with LRU cache + async compute"
```

---

## Task 6: `PreviewRenderers` — 6 개 상태별 렌더러

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Preview/PreviewRenderers.swift`

각 상태별 단일 SwiftUI view. 파일 크기 · 수정 시각 · 확장자 같은 공통 메타는 상위 `PreviewPaneView` 에서 한 번만 렌더.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI
import AppKit

// MARK: - Idle

struct IdlePreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a file to preview")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading

struct LoadingPreview: View {
    var body: some View {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Text

struct TextPreview: View {
    let body_: String

    init(_ text: String) { self.body_ = text }

    var body: some View {
        ScrollView {
            Text(body_)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}

// MARK: - Image

/// Async-loads NSImage off the main thread so large files don't stall UI.
/// Scales proportional fit inside 256pt content box.
struct ImagePreview: View {
    let path: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 256, maxHeight: 256)
            } else {
                LoadingPreview()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            let p = path
            let decoded = await Task.detached { NSImage(contentsOf: URL(fileURLWithPath: p)) }.value
            image = decoded
        }
    }
}

// MARK: - Directory

struct DirectoryPreview: View {
    let childCount: Int
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            Text(childCount == 1 ? "1 item" : "\(childCount) items")
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Binary / Failed

struct BinaryPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.doc")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Preview not available (binary file)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailedPreview: View {
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: 빌드 — 이 파일 단독으로 컴파일 OK**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Preview/PreviewRenderers.swift
git commit -m "feat(preview): add PreviewRenderers (idle/loading/text/image/directory/binary/failed)"
```

---

## Task 7: `PreviewPaneView` — 상태 → 렌더러 라우팅

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Preview/PreviewPaneView.swift`

`PreviewModel.state` 를 switch 해서 적절한 renderer 리턴. focus URL 의 기본 메타 (파일명 + 경로 + 크기) 를 상단에 얇게 표시.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI
import Foundation

/// Detail-pane root. Shows an optional metadata header + the renderer matching
/// the current PreviewState. The header is suppressed in .idle to keep the
/// empty state visually quiet.
struct PreviewPaneView: View {
    @Bindable var preview: PreviewModel

    var body: some View {
        VStack(spacing: 0) {
            if let url = preview.focus, !isIdle {
                header(for: url)
                Divider()
            }
            renderer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isIdle: Bool {
        if case .idle = preview.state { return true }
        return false
    }

    @ViewBuilder
    private var renderer: some View {
        switch preview.state {
        case .idle:
            IdlePreview()
        case .loading:
            LoadingPreview()
        case .text(let s):
            TextPreview(s)
        case .image(let path):
            ImagePreview(path: path)
        case .directory(let n):
            DirectoryPreview(childCount: n)
        case .binary:
            BinaryPreview()
        case .failed(let m):
            FailedPreview(message: m)
        }
    }

    private func header(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            if let size = fileSize(for: url) {
                Text(size)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileSize(for url: URL) -> String? {
        guard let n = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 아직 ContentView 에 연결 안 됐으니 앱 동작은 그대로.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Preview/PreviewPaneView.swift
git commit -m "feat(preview): add PreviewPaneView with metadata header + renderer routing"
```

---

## Task 8: `Space` → QLPreviewPanel 통합

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListNSTableView.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

QLPreviewPanel 은 first-responder NSView 에 `-acceptsPreviewPanelControl` / `-begin/-endPreviewPanelControl` 을 물어봄. Responder = `FileListNSTableView`. Panel dataSource/delegate 는 Coordinator.

- [ ] **Step 1: `FileListNSTableView.swift` — Space keyDown + panel control 오버라이드**

현재 파일 (`activationHandler` + `menuHandler` 있음) 을 다음으로 교체:

```swift
import AppKit
import QuickLookUI

/// NSTableView subclass that surfaces ⏎/Enter (activation), right-click (menu),
/// and Space (Quick Look) as events the Coordinator can handle. Also participates
/// in the QLPreviewPanel responder-chain protocol so Space opens a preview of the
/// selected files.
final class FileListNSTableView: NSTableView {
    /// Fired on ⏎ / numpad-Enter.
    var activationHandler: (() -> Void)?

    /// Returned by AppKit when the user right-clicks.
    var menuHandler: ((NSEvent) -> NSMenu?)?

    /// Sets the panel's dataSource/delegate when Quick Look takes control. The
    /// Coordinator is the actual QL delegate — it owns the snapshot + selection
    /// state needed to answer QL's queries.
    weak var quickLookDelegate: (NSObject & QLPreviewPanelDataSource & QLPreviewPanelDelegate)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return (main kb), 76 = numpad Enter, 49 = Space.
        switch event.keyCode {
        case 36, 76:
            activationHandler?()
        case 49:
            if let panel = QLPreviewPanel.shared() {
                panel.makeKeyAndOrderFront(nil)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let handler = menuHandler {
            return handler(event)
        }
        return super.menu(for: event)
    }

    // MARK: - QLPreviewPanel responder-chain hooks

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookDelegate
        panel.delegate = quickLookDelegate
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

- [ ] **Step 2: `FileListCoordinator.swift` — QL dataSource/delegate 추가**

파일 상단 `import AppKit` 옆에 추가:

```swift
import QuickLookUI
```

클래스 선언부의 `final class FileListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {` 를 다음으로 교체 — 인터페이스 두 개 추가:

```swift
final class FileListCoordinator: NSObject,
                                 NSTableViewDataSource,
                                 NSTableViewDelegate,
                                 QLPreviewPanelDataSource,
                                 QLPreviewPanelDelegate {
```

클래스 끝부분 `// MARK: - Private helpers` 바로 위에 새 섹션 추가:

```swift
    // MARK: - Quick Look

    /// Snapshot of the paths currently selected at the moment QL took control.
    /// Captured in begin to avoid races with live selection changes while the
    /// panel is up.
    private var quickLookURLs: [URL] {
        let selectedRows = table?.selectedRowIndexes ?? IndexSet()
        let paths: [URL] = selectedRows.compactMap { row in
            guard row < lastSnapshot.count else { return nil }
            let p = lastSnapshot[row].path.toString()
            return URL(fileURLWithPath: p)
        }
        // Fallback: if nothing is selected but the user pressed Space, preview
        // the clicked / first row.
        if paths.isEmpty, !lastSnapshot.isEmpty {
            let p = lastSnapshot[0].path.toString()
            return [URL(fileURLWithPath: p)]
        }
        return paths
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let urls = quickLookURLs
        guard index >= 0, index < urls.count else { return nil }
        return urls[index] as NSURL
    }
```

- [ ] **Step 3: `FileListView.makeNSView` — `quickLookDelegate` wire-up**

`FileListView.swift` 의 `makeNSView` 안, `table.menuHandler = { ... }` 블록 바로 아래에 다음 추가:

```swift
        // Quick Look (Space): route panel queries to the Coordinator.
        table.quickLookDelegate = context.coordinator
```

- [ ] **Step 4: 빌드 — `** BUILD SUCCEEDED **`**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

빌드 실패 시 흔한 원인: `QuickLookUI` 프레임워크가 자동 linked 안 됨. xcodegen `project.yml` 의 `dependencies` 에 `sdk: QuickLookUI.framework` 를 추가해야 할 수도 있음. 먼저 빌드 에러 메시지 확인 후 조치.

만약 링커 에러 (`Undefined symbol: _OBJC_CLASS_$_QLPreviewPanel`) 면:

`apps/project.yml` 의 target Cairn 섹션 `dependencies:` 아래에 추가 (기존 deps 뒤에 이어 붙임):

```yaml
      - sdk: QuickLookUI.framework
```

그 후 `xcodegen generate` 재실행.

- [ ] **Step 5: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20 통과.

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListNSTableView.swift apps/Sources/Views/FileList/FileListCoordinator.swift apps/Sources/Views/FileList/FileListView.swift
# If project.yml was modified:
git add apps/project.yml apps/Sources/Generated 2>/dev/null || true
git commit -m "feat(file-list): Space → QLPreviewPanel via responder-chain integration"
```

---

## Task 9: ContentView — PreviewPaneView + `⌘⇧.` + selection → preview focus

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/App/AppModel.swift` (주입)
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift` (UI 연결)
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListView.swift` (`onSelectionChanged` 콜백 추가)
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift` (콜백 호출)

preview focus 는 선택된 첫 행의 path 를 URL 로 넘기는 콜백으로 전달. 콜백은 `tableViewSelectionDidChange` 에서 호출.

- [ ] **Step 1: `AppModel.swift` — PreviewModel 주입**

현재 `AppModel.swift` 의 저장 프로퍼티 블록 (`let engine`, `let bookmarks`, `let lastFolder`, `let mountObserver`, `let sidebar`) 바로 아래에 추가:

```swift
    let preview: PreviewModel
```

init 내부, `self.sidebar = SidebarModel(mountObserver: observer)` 바로 아래, `bootstrapInitialFolder()` 호출 바로 위에 추가:

```swift
        self.preview = PreviewModel(engine: engine)
```

- [ ] **Step 2: `FileListCoordinator.swift` — `onSelectionChanged` 콜백 주입**

init 파라미터 블록 — 현재 시그니처:

```swift
    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool) {
```

을 다음으로 교체:

```swift
    private let onSelectionChanged: (FileEntry?) -> Void

    init(folder: FolderModel,
         onActivate: @escaping (FileEntry) -> Void,
         onAddToPinned: @escaping (FileEntry) -> Void,
         isPinnedCheck: @escaping (FileEntry) -> Bool,
         onSelectionChanged: @escaping (FileEntry?) -> Void) {
        self.folder = folder
        self.onActivate = onActivate
        self.onAddToPinned = onAddToPinned
        self.isPinnedCheck = isPinnedCheck
        self.onSelectionChanged = onSelectionChanged
        super.init()
    }
```

그리고 `tableViewSelectionDidChange(_:)` 메서드 — 기존:

```swift
    func tableViewSelectionDidChange(_ notification: Notification) {
        if isApplyingModelUpdate { return }
        guard let table = notification.object as? NSTableView else { return }
        let paths = table.selectedRowIndexes.compactMap { row -> String? in
            guard row < lastSnapshot.count else { return nil }
            return lastSnapshot[row].path.toString()
        }
        folder.setSelection(Set(paths))
    }
```

다음으로 교체 (기존 동작 + 콜백 호출 추가):

```swift
    func tableViewSelectionDidChange(_ notification: Notification) {
        if isApplyingModelUpdate { return }
        guard let table = notification.object as? NSTableView else { return }
        let rows = table.selectedRowIndexes
        let paths = rows.compactMap { row -> String? in
            guard row < lastSnapshot.count else { return nil }
            return lastSnapshot[row].path.toString()
        }
        folder.setSelection(Set(paths))

        // Preview focus: first-selected row's entry (row-order, not Set-order).
        let firstRow = rows.min()
        let firstEntry: FileEntry? = firstRow.flatMap { row in
            row < lastSnapshot.count ? lastSnapshot[row] : nil
        }
        onSelectionChanged(firstEntry)
    }
```

- [ ] **Step 3: `FileListView.swift` — `onSelectionChanged` stored property + makeCoordinator**

저장 프로퍼티 블록 — 기존:

```swift
    let onActivate: (FileEntry) -> Void
    let onAddToPinned: (FileEntry) -> Void
    let isPinnedCheck: (FileEntry) -> Bool
```

다음으로 교체 (한 줄 추가):

```swift
    let onActivate: (FileEntry) -> Void
    let onAddToPinned: (FileEntry) -> Void
    let isPinnedCheck: (FileEntry) -> Bool
    let onSelectionChanged: (FileEntry?) -> Void
```

`makeCoordinator()` 교체:

```swift
    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(folder: folder,
                            onActivate: onActivate,
                            onAddToPinned: onAddToPinned,
                            isPinnedCheck: isPinnedCheck,
                            onSelectionChanged: onSelectionChanged)
    }
```

- [ ] **Step 4: `ContentView.swift` — preview wiring + `⌘⇧.`**

`ContentView.swift` 의 `body` 내부:

기존 `FileListView(...)` 호출:

```swift
                FileListView(
                    folder: folder,
                    onActivate: handleOpen,
                    onAddToPinned: handleAddToPinned,
                    isPinnedCheck: { entry in
                        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                    }
                )
```

다음으로 교체 (새 콜백 추가):

```swift
                FileListView(
                    folder: folder,
                    onActivate: handleOpen,
                    onAddToPinned: handleAddToPinned,
                    isPinnedCheck: { entry in
                        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                    },
                    onSelectionChanged: handleSelectionChanged
                )
```

기존 detail 클로저:

```swift
        } detail: {
            previewPlaceholder
        }
```

을 다음으로 교체:

```swift
        } detail: {
            PreviewPaneView(preview: app.preview)
        }
```

기존 `previewPlaceholder` 프로퍼티는 그대로 두면 unused dead code 남음. 파일에서 다음 블록을 **삭제**:

```swift
    private var previewPlaceholder: some View {
        VStack {
            Text("PREVIEW")
                .font(.caption).foregroundStyle(.secondary)
            Text("M1.4").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
```

그리고 `toolbar { ... }` 블록 안의 `⌘D` 버튼 (`placement: .automatic`) 다음에 새 toolbar item 추가:

```swift
            ToolbarItem(placement: .automatic) {
                Button(action: { toggleShowHidden() }) {
                    Image(systemName: app.showHidden ? "eye" : "eye.slash")
                }
                .help(app.showHidden ? "Hide hidden files" : "Show hidden files")
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
```

끝으로, `handleAddToPinned(_:)` 메서드 다음에 두 helper 메서드 추가:

```swift
    private func handleSelectionChanged(_ entry: FileEntry?) {
        if let e = entry {
            app.preview.focus = URL(fileURLWithPath: e.path.toString())
        } else {
            app.preview.focus = nil
        }
    }

    private func toggleShowHidden() {
        app.toggleShowHidden()
        if let url = app.currentFolder {
            Task { await folder?.load(url) }
        }
    }
```

- [ ] **Step 5: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 에러 있으면 STOP.

- [ ] **Step 6: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 7: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/App/AppModel.swift apps/Sources/ContentView.swift apps/Sources/Views/FileList/FileListView.swift apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(preview): wire PreviewPaneView + selection focus + ⌘⇧. hidden toggle"
```

---

## Task 10: 수동 E2E (사용자 수행)

**Files:** 없음 (검증만)

- [ ] **Step 1: 앱 빌드 + 실행**

```bash
cd /Users/cyj/workspace/personal/cairn
./scripts/build-rust.sh
./scripts/gen-bindings.sh
cd apps && xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Cairn.app" -type d 2>/dev/null | grep Debug | head -1)
open "$APP"
```

- [ ] **Step 2: 체크리스트 (사용자 수행)**

- [ ] 파일 단일 선택 → detail 패널에 메타 헤더 (파일명 / 경로 / 크기) + 내용 렌더
- [ ] **텍스트 파일** (.txt, .md, .swift, .rs 등) → monospace 로 렌더, 스크롤 가능, 텍스트 선택 가능
- [ ] **64KB 초과 파일** → 끝에 `…(truncated)` 표시
- [ ] **이미지 파일** (.png, .jpg 등) → 썸네일 렌더, 256pt 박스 안 fit
- [ ] **바이너리 파일** (예: 실행 파일, .zip) → "Preview not available (binary file)"
- [ ] **폴더 선택** → "N items" 표시
- [ ] **선택 해제** → idle state ("Select a file to preview")
- [ ] **여러 파일 선택** → 첫 행 기준 프리뷰
- [ ] **같은 파일 두 번째 선택** → 캐시 덕에 즉시 (loading 없이) 보임
- [ ] **`Space`** → QLPreviewPanel 뜸 / `Esc` or `Space` 재누름 → 닫힘
- [ ] **여러 파일 선택 + `Space`** → QLPanel 에서 좌우 화살표로 순회 가능
- [ ] **`⌘⇧.`** → 숨김 파일 토글 (`.DS_Store` 등 보였다 사라졌다), toolbar eye 아이콘 변화
- [ ] **M1.3 regression** — 사이드바 4 섹션 / ⌘D / 우클릭 / 브레드크럼 모두 정상
- [ ] **M1.2 regression** — 컬럼 정렬 / ↑↓ / ⏎ / 더블클릭 모두 정상

문제 발견 시 어떤 항목이 안 되는지 메모, STOP.

- [ ] **Step 3: 커밋 불필요**

---

## Task 11: 워크스페이스 sanity + tag

**Files:** 없음 (검증 + tag)

- [ ] **Step 1: 로컬 CI**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -3)
(cd apps && xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | grep -E "Executed|TEST" | tail -5)
```

Expected:
- fmt: clean
- clippy: clean
- cargo test: 기존 + cairn-preview 6 + cairn-ffi 1 추가 → 합 22 이상 통과 (정확한 수는 Task 1/2/3 이 합쳐진 실제 결과로)
- build-rust / gen-bindings: pass
- xcodebuild build: PASS
- xcodebuild test: 20/20

- [ ] **Step 2: fmt 실패 시 자동 정렬**

```bash
cargo fmt --all
git diff --stat
# 변경 있으면:
git add -A crates/
git commit -m "style: cargo fmt"
```

- [ ] **Step 3: tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.4
git log --oneline phase-1-m1.3..phase-1-m1.4
```

Expected: M1.4 커밋 약 9 개.

- [ ] **Step 4: tag 확인**

```bash
git tag -l | grep phase
```

Expected: `phase-1-m1.1`, `phase-1-m1.2`, `phase-1-m1.3`, `phase-1-m1.4`.

---

## 🎯 M1.4 Definition of Done

- [ ] Rust `cairn-preview::preview_text` 구현 + 6 단위 테스트 (통과)
- [ ] `cairn-core::Engine::preview_text` re-export
- [ ] `cairn-ffi` PreviewError + `engine.preview_text` Swift 바인딩 + 1 smoke test
- [ ] `CairnEngine.previewText(_:) async throws -> String` 추가 + `extension PreviewError: Error {}`
- [ ] `PreviewModel` LRU 16 캐시 + focus 기반 async 로딩 + 3 단위 테스트
- [ ] `PreviewRenderers` 6 상태 (Idle / Loading / Text / Image / Directory / Binary / Failed)
- [ ] `PreviewPaneView` state 라우팅 + 메타 헤더
- [ ] `Space` → QLPreviewPanel (FileListNSTableView + Coordinator delegate)
- [ ] `⌘⇧.` → 숨김 파일 토글 + 자동 reload
- [ ] Preview focus 는 FolderModel selection 의 첫 행 (row-order)
- [ ] `xcodebuild test` 20/20 통과
- [ ] `cargo test --workspace` + `cargo clippy -- -D warnings` 녹색
- [ ] `git tag phase-1-m1.4` 존재

---

## 이월된 follow-up (M1.5 에서 처리)

- M1.2 review 에서 올라온 것들 (sortDescriptorsDidChange 재진입 주석, `@Bindable var folder` → `let`, `modified_unix==0` sentinel docstring, `activateSelected` multi-row)
- M1.3 review 에서 올라온 것들 (`representedObject` 안전성 — MenuPayload 리팩터, 사이드바 selection highlight, `SidebarModelTests` 반응성 테스트 누락, `isPinned(url:)` plan 스펙 drift)
- M1.4 잠재 이슈들 (아래 섹션)

## M1.4 에서 알려진 polish 항목 (M1.5 에서 같이)

- `PreviewModel.compute` 내 `RustString` 에서 `.toString()` 호출하는 line 은 Swift 쪽에서 자동이나, `PreviewError.Io(msg)` 의 `msg` 는 `RustString` — `.toString()` 필요 (코드에 이미 포함됨, 재확인용).
- `ImagePreview` 의 `task(id: path)` 는 URL 이 바뀔 때 취소/재시작을 잘 해주지만, 거대 이미지 (수백 MB) 는 NSImage init 도 느림 — 썸네일 생성 scale 은 M1.5 에서 `CGImageSource` 로 교체 고려.
- `⌘⇧.` 가 `folder?.load` 를 직접 호출하는데 load 동안 이전 entries 는 유지 — flicker 없지만 state 가 `.loading` 으로 안 잠깐 바뀜. M1.5 theme 에 맞춰 loading indicator 개선.
- QLPreviewPanel 에서 여러 파일 순회 시 first-responder 관리. `FileListNSTableView` 가 window key loss 시 panel 이 empty 될 가능성 — 실사용 regression 나오면 M1.6 에서.

---

## 다음 마일스톤 (M1.5)

M1.5 는 **디자인 + context menu 확장**:
- `CairnTheme` 토큰 (palette, typography, spacing)
- Glass Blue 팔레트 + `NSVisualEffectView` (사이드바 / 툴바 반투명)
- 파일 리스트 우클릭 메뉴 확장 (Copy Path / Open With / Move to Trash)
- 사이드바 현재 폴더 highlight
- M1.2/M1.3/M1.4 이월된 polish 흡수
- `⌘R` reload

M1.5 플랜은 M1.4 완료 직후 작성 (실행 러닝 반영).
