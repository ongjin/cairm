# Cairn Phase 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Cairn 프로젝트의 end-to-end 아키텍처를 "Hello, Cairn!" 수준으로 완전 결선한다. Rust 엔진(swift-bridge로 래핑) → Swift UI(SwiftUI)로 문자열이 흘러오는 파이프라인을 증명하고, CI가 녹색이면 끝.

**Architecture:** Monorepo 안에 Rust Cargo workspace(여러 크레이트) + Xcode 프로젝트(xcodegen 생성). swift-bridge가 Rust 함수 → Swift API 자동 생성. 빌드 스크립트가 Rust를 유니버셜 static lib(arm64+x86_64)로 빌드 → Xcode가 링크 → SwiftUI가 호출.

**Tech Stack:** Rust 1.75+ · Cargo workspace · swift-bridge 0.1.x · macOS 13+ · Swift 5.9+ · SwiftUI · xcodegen · GitHub Actions

**Working directory:** `/Users/cyj/workspace/personal/cairn` (git repo, main branch, 스펙 커밋이 `336a386`로 존재)

**Deliverable verification:**
- `xcodebuild -scheme Cairn -configuration Debug build` → 성공
- 앱 실행 시 SwiftUI 윈도우에 `Hello, Cairn! (from Rust)` 표시
- `cargo test --workspace` → 녹색
- GitHub Actions CI → 녹색

---

## File Structure

이 Phase 0에서 생성될 파일:

**프로젝트 루트:**
- `README.md` — 프로젝트 소개, 빌드 방법
- `LICENSE` — MIT 라이선스 전문
- `Cargo.toml` — Workspace 루트

**Rust 크레이트 (모두 `crates/` 아래):**
- `cairn-core/` — 퍼사드. Phase 0엔 skeleton `pub fn hello() -> String`만.
- `cairn-walker/` — 빈 skeleton (Phase 1에서 구현)
- `cairn-search/` — 빈 skeleton (Phase 2)
- `cairn-preview/` — 빈 skeleton (Phase 2)
- `cairn-index/` — 빈 skeleton (Phase 2)
- `cairn-ffi/` — swift-bridge 정의. Phase 0엔 `greet()` 함수 하나만.

**Swift 앱:**
- `apps/Cairn/` — SwiftUI 앱 소스
  - `Sources/CairnApp.swift` — @main 엔트리
  - `Sources/ContentView.swift` — 초기 뷰
  - `Sources/BridgingHeader.h` — C 헤더 연결
- `apps/project.yml` — xcodegen 설정
- `apps/Cairn.xcodeproj/` — xcodegen이 생성 (gitignore)

**빌드/CI:**
- `scripts/build-rust.sh` — 유니버셜 static lib 빌드
- `scripts/gen-bindings.sh` — swift-bridge 바인딩 생성
- `.github/workflows/ci.yml` — GitHub Actions

**생성되는 중간 산물 (gitignore):**
- `target/` — Cargo 빌드 출력
- `apps/Cairn.xcodeproj/`
- `apps/Sources/Generated/` — swift-bridge가 생성한 Swift 소스

---

## Task 1: 프로젝트 문서화 (README + LICENSE)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/README.md`
- Create: `/Users/cyj/workspace/personal/cairn/LICENSE`
- Modify: `/Users/cyj/workspace/personal/cairn/.gitignore`

- [x] **Step 1: README.md 작성**

파일 내용:

```markdown
# Cairn

The most beautiful open-source file manager for macOS. Built with SwiftUI + Rust.

> ⚠️ **Status:** Phase 0 — Foundation. Not usable yet. See [design spec](./docs/superpowers/specs/2026-04-21-cairn-design.md).

## Features (v1.0 target)

- **Multi-theme** — Glass (default) · Arc · Raycast
- **⌘K Command Palette** — navigation + actions + search, one input
- **Lightning search** — ripgrep-powered, .gitignore-aware

## Architecture

```
SwiftUI app  ──swift-bridge──►  Rust engine (workspace crates)
```

## Build

Prerequisites: Xcode 15+, Rust 1.75+, [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
# Install xcodegen if needed
brew install xcodegen

# Build Rust engine
./scripts/build-rust.sh

# Generate swift-bridge bindings
./scripts/gen-bindings.sh

# Generate Xcode project
cd apps && xcodegen generate

# Build & run
xcodebuild -scheme Cairn -configuration Debug build
open apps/build/Debug/Cairn.app
```

## License

MIT — see [LICENSE](./LICENSE).
```

- [x] **Step 2: LICENSE 작성 (MIT 전문)**

파일 내용:

```
MIT License

Copyright (c) 2026 ongjin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [x] **Step 3: .gitignore에 Xcode·생성물 추가 (기존 파일 수정)**

기존 `.gitignore` 내용 끝에 다음을 추가하세요 (이미 있는 항목은 건드리지 말 것):

```
# xcodegen이 생성하는 프로젝트 파일
apps/Cairn.xcodeproj/

# swift-bridge가 생성하는 Swift 바인딩
apps/Sources/Generated/

# swift-bridge build cache
generated/
```

- [x] **Step 4: 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
ls -1 README.md LICENSE .gitignore
cat .gitignore | tail -10
```

Expected: 세 파일 모두 존재. `.gitignore` 끝에 새로 추가한 항목 보임.

- [x] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add README.md LICENSE .gitignore
git commit -m "docs: add README and MIT LICENSE"
```

---

## Task 2: Cargo Workspace 루트

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/Cargo.toml`
- Create: `/Users/cyj/workspace/personal/cairn/rust-toolchain.toml`

- [x] **Step 1: Workspace `Cargo.toml` 작성**

파일 내용:

```toml
[workspace]
resolver = "2"
members = [
    "crates/cairn-core",
    "crates/cairn-walker",
    "crates/cairn-search",
    "crates/cairn-preview",
    "crates/cairn-index",
    "crates/cairn-ffi",
]

[workspace.package]
version = "0.0.1"
edition = "2021"
rust-version = "1.75"
authors = ["ongjin"]
license = "MIT"
repository = "https://github.com/ongjin/cairn"

[workspace.dependencies]
# Phase 0에선 거의 안 쓰임. Phase 1+에서 채워진다.
# 여기 등록된 의존성은 하위 크레이트에서 `workspace = true`로 참조.
anyhow = "1"
thiserror = "1"

[profile.release]
lto = true
codegen-units = 1
strip = true
```

- [x] **Step 2: `rust-toolchain.toml` 작성 (툴체인 고정)**

파일 내용:

```toml
[toolchain]
channel = "1.75.0"
components = ["rustfmt", "clippy"]
targets = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
```

- [x] **Step 3: Workspace가 파싱되는지 확인 (크레이트 없어서 실패 예상)**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo metadata --format-version=1 2>&1 | head -5
```

Expected: `error: failed to load manifest for workspace member ...crates/cairn-core` 같은 에러. 멤버 크레이트가 아직 없으므로 정상.

이 상태는 다음 태스크에서 크레이트를 만들면 풀린다.

- [x] **Step 4: 커밋**

```bash
git add Cargo.toml rust-toolchain.toml
git commit -m "build(rust): add cargo workspace root and toolchain pin"
```

---

## Task 3: `cairn-core` 크레이트 (skeleton + hello)

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/crates/cairn-core/Cargo.toml`
- Create: `/Users/cyj/workspace/personal/cairn/crates/cairn-core/src/lib.rs`

- [x] **Step 1: 실패하는 테스트 작성**

`crates/cairn-core/Cargo.toml`:

```toml
[package]
name = "cairn-core"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_core"
```

`crates/cairn-core/src/lib.rs`:

```rust
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
```

- [x] **Step 2: 테스트 실행 — 통과 확인**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo test -p cairn-core
```

Expected: `test hello_returns_expected_greeting ... ok`, `test result: ok. 1 passed`

(이 케이스는 함수 구현이 너무 단순해서 실패하는 단계를 건너뛴다. 의도적.)

- [x] **Step 3: 커밋**

```bash
git add crates/cairn-core
git commit -m "feat(core): add hello() skeleton with test"
```

---

## Task 4: 나머지 4개 스켈레톤 크레이트 (walker / search / preview / index)

Phase 0엔 각 크레이트의 존재만 등록한다. 실제 로직은 Phase 1+에서 추가. 파일 구조만 세워두면 workspace 파싱이 성공한다.

**Files:**
- Create: `crates/cairn-walker/Cargo.toml` + `src/lib.rs`
- Create: `crates/cairn-search/Cargo.toml` + `src/lib.rs`
- Create: `crates/cairn-preview/Cargo.toml` + `src/lib.rs`
- Create: `crates/cairn-index/Cargo.toml` + `src/lib.rs`

- [x] **Step 1: `cairn-walker` 스켈레톤**

`crates/cairn-walker/Cargo.toml`:

```toml
[package]
name = "cairn-walker"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_walker"
```

`crates/cairn-walker/src/lib.rs`:

```rust
//! cairn-walker — filesystem traversal with .gitignore awareness.
//!
//! Phase 1 implementation. Skeleton for now.

#[cfg(test)]
mod tests {
    #[test]
    fn crate_compiles() {
        // Placeholder — real tests land in Phase 1.
    }
}
```

- [x] **Step 2: `cairn-search` 스켈레톤 (동일 패턴)**

`crates/cairn-search/Cargo.toml`:

```toml
[package]
name = "cairn-search"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_search"
```

`crates/cairn-search/src/lib.rs`:

```rust
//! cairn-search — filename fuzzy + content search.
//!
//! Phase 2 implementation. Skeleton for now.

#[cfg(test)]
mod tests {
    #[test]
    fn crate_compiles() {}
}
```

- [x] **Step 3: `cairn-preview` 스켈레톤**

`crates/cairn-preview/Cargo.toml`:

```toml
[package]
name = "cairn-preview"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_preview"
```

`crates/cairn-preview/src/lib.rs`:

```rust
//! cairn-preview — syntax highlighting, thumbnails, structured previews.
//!
//! Phase 2 implementation. Skeleton for now.

#[cfg(test)]
mod tests {
    #[test]
    fn crate_compiles() {}
}
```

- [x] **Step 4: `cairn-index` 스켈레톤**

`crates/cairn-index/Cargo.toml`:

```toml
[package]
name = "cairn-index"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
name = "cairn_index"
```

`crates/cairn-index/src/lib.rs`:

```rust
//! cairn-index — incremental index cache (redb-backed).
//!
//! Phase 2 implementation. Skeleton for now.

#[cfg(test)]
mod tests {
    #[test]
    fn crate_compiles() {}
}
```

- [x] **Step 5: Workspace 전체 빌드·테스트**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo build --workspace
cargo test --workspace
```

Expected:
- `cargo build`: `Compiling cairn-core v0.0.1`, `Compiling cairn-walker v0.0.1`, ... `Finished dev [unoptimized + debuginfo] target(s)`
- `cargo test`: `test result: ok. 1 passed` for cairn-core, `0 passed` for 나머지 4개.

- [x] **Step 6: 커밋**

```bash
git add crates/cairn-walker crates/cairn-search crates/cairn-preview crates/cairn-index
git commit -m "feat(crates): add skeleton crates for walker, search, preview, index"
```

---

## Task 5: `cairn-ffi` 크레이트 (swift-bridge 설정)

swift-bridge는 Rust proc macro로 FFI 정의를 받아 Swift 소스와 C 헤더를 생성한다. 빌드 스크립트(`build.rs`)가 이걸 구동.

**Files:**
- Create: `crates/cairn-ffi/Cargo.toml`
- Create: `crates/cairn-ffi/build.rs`
- Create: `crates/cairn-ffi/src/lib.rs`

- [x] **Step 1: `cairn-ffi/Cargo.toml` 작성**

```toml
[package]
name = "cairn-ffi"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
# cdylib: Swift dynamic linking. staticlib: universal static 링크 (Xcode가 선호).
# 둘 다 만들어두면 상황별로 골라 쓸 수 있다. Phase 0은 staticlib 사용.
crate-type = ["staticlib", "rlib"]
name = "cairn_ffi"

[dependencies]
cairn-core = { path = "../cairn-core" }
swift-bridge = "0.1"

[build-dependencies]
swift-bridge-build = "0.1"
```

- [x] **Step 2: `build.rs` 작성 (바인딩 생성기)**

`crates/cairn-ffi/build.rs`:

```rust
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
```

- [x] **Step 3: `src/lib.rs`에 브리지 정의 작성**

`crates/cairn-ffi/src/lib.rs`:

```rust
//! cairn-ffi — the only crate the Swift app sees.
//!
//! Defines swift-bridge modules that expose Rust functions as Swift APIs.
//! Phase 0 exposes a single `greet()` to prove the pipeline.

#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        /// Returns a greeting string from the Rust engine.
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
```

- [x] **Step 4: 빌드 및 테스트**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo build -p cairn-ffi
cargo test -p cairn-ffi
```

Expected:
- `cargo build`: `Compiling cairn-ffi v0.0.1`, 성공
- 생성된 바인딩 확인: `ls crates/cairn-ffi/generated/cairn_ffi/` → `cairn_ffi.swift`, `cairn_ffi.h` 존재
- `cargo test`: `test greet_wraps_core_hello ... ok`

- [x] **Step 5: 생성 파일 내용 훑어보기 (디버그용, 실수 없는지 확인)**

```bash
cat crates/cairn-ffi/generated/cairn_ffi/cairn_ffi.swift | head -30
cat crates/cairn-ffi/generated/cairn_ffi/cairn_ffi.h | head -30
```

Expected:
- `cairn_ffi.swift`: `public func greet() -> RustString { ... }` 같은 라인 보임
- `cairn_ffi.h`: `void* __swift_bridge__$greet(void);` 같은 C 선언 보임

- [x] **Step 6: 커밋**

```bash
git add crates/cairn-ffi
git commit -m "feat(ffi): add swift-bridge scaffolding with greet() function"
```

---

## Task 6: Rust 유니버셜 static lib 빌드 스크립트

arm64 (Apple Silicon) + x86_64 (Intel) 둘 다 빌드해서 `lipo`로 합쳐 하나의 유니버셜 파일 생성. Xcode가 링크할 최종 산물.

**Files:**
- Create: `scripts/build-rust.sh`
- Create: `scripts/gen-bindings.sh`

- [x] **Step 1: `scripts/build-rust.sh` 작성**

```bash
#!/usr/bin/env bash
# Build the Rust static library for Cairn as a universal macOS binary.
# Output: target/universal/release/libcairn_ffi.a

set -euo pipefail

cd "$(dirname "$0")/.."

CRATE="cairn-ffi"
LIB="libcairn_ffi.a"
TARGET_DIR="target"
OUT_DIR="$TARGET_DIR/universal/release"

echo "▸ Ensuring Rust targets are installed..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "▸ Building $CRATE for aarch64-apple-darwin..."
cargo build --release -p "$CRATE" --target aarch64-apple-darwin

echo "▸ Building $CRATE for x86_64-apple-darwin..."
cargo build --release -p "$CRATE" --target x86_64-apple-darwin

echo "▸ Creating universal binary at $OUT_DIR/$LIB..."
mkdir -p "$OUT_DIR"
lipo -create \
  "$TARGET_DIR/aarch64-apple-darwin/release/$LIB" \
  "$TARGET_DIR/x86_64-apple-darwin/release/$LIB" \
  -output "$OUT_DIR/$LIB"

echo "▸ Verifying architectures..."
lipo -info "$OUT_DIR/$LIB"

echo "✓ Built universal static lib: $OUT_DIR/$LIB"
```

- [x] **Step 2: `scripts/gen-bindings.sh` 작성 (바인딩을 Xcode가 참조하는 위치로 복사)**

```bash
#!/usr/bin/env bash
# Generate swift-bridge Swift/C bindings by invoking cargo build on cairn-ffi,
# then mirror the generated sources into apps/Sources/Generated/ for Xcode.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "▸ Running cargo build to regenerate bindings..."
cargo build -p cairn-ffi

SRC="crates/cairn-ffi/generated/cairn_ffi"
DST="apps/Sources/Generated"

if [[ ! -d "$SRC" ]]; then
  echo "✗ Bindings not found at $SRC — did cargo build succeed?"
  exit 1
fi

mkdir -p "$DST"
cp "$SRC/cairn_ffi.swift" "$DST/cairn_ffi.swift"
cp "$SRC/cairn_ffi.h" "$DST/cairn_ffi.h"

# swift-bridge runtime Swift sources (공용 헬퍼)
SWIFT_BRIDGE_SRC="$(find target -name 'SwiftBridgeCore.swift' -path '*/swift-bridge-*/*' | head -1)"
if [[ -n "$SWIFT_BRIDGE_SRC" ]]; then
  cp "$SWIFT_BRIDGE_SRC" "$DST/SwiftBridgeCore.swift"
  SWIFT_BRIDGE_H="$(dirname "$SWIFT_BRIDGE_SRC")/SwiftBridgeCore.h"
  cp "$SWIFT_BRIDGE_H" "$DST/SwiftBridgeCore.h"
fi

echo "✓ Bindings copied to $DST/"
ls -1 "$DST"
```

- [x] **Step 3: 스크립트 실행 권한 부여 + 실행**

```bash
chmod +x scripts/build-rust.sh scripts/gen-bindings.sh

# 유니버셜 static lib 빌드 (처음엔 5~10분 걸릴 수 있음 — dep 컴파일)
./scripts/build-rust.sh
```

Expected 출력 끝부분:
```
▸ Verifying architectures...
Architectures in the fat file: target/universal/release/libcairn_ffi.a are: x86_64 arm64
✓ Built universal static lib: target/universal/release/libcairn_ffi.a
```

- [x] **Step 4: 바인딩 복사 스크립트 실행**

```bash
./scripts/gen-bindings.sh
```

Expected 출력 끝부분:
```
✓ Bindings copied to apps/Sources/Generated/
cairn_ffi.h
cairn_ffi.swift
SwiftBridgeCore.h      (swift-bridge 버전에 따라 없을 수 있음)
SwiftBridgeCore.swift  (swift-bridge 버전에 따라 없을 수 있음)
```

- [x] **Step 5: 커밋 (생성된 바인딩은 gitignore이므로 스크립트만 커밋)**

```bash
git add scripts/build-rust.sh scripts/gen-bindings.sh
git commit -m "build: add rust universal build script and bindings copy script"
```

---

## Task 7: Minimal SwiftUI 앱 + xcodegen 설정

`xcodegen`은 YAML에서 Xcode 프로젝트를 생성한다. 버전 컨트롤 친화적.

**Files:**
- Create: `apps/project.yml`
- Create: `apps/Sources/CairnApp.swift`
- Create: `apps/Sources/ContentView.swift`
- Create: `apps/Sources/BridgingHeader.h`

- [x] **Step 1: xcodegen 설치 확인**

```bash
which xcodegen || brew install xcodegen
xcodegen --version
```

Expected: 버전 번호 출력 (예: `2.39.1`).

- [x] **Step 2: `apps/Sources/CairnApp.swift` — 앱 엔트리**

```swift
import SwiftUI

@main
struct CairnApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
```

- [x] **Step 3: `apps/Sources/ContentView.swift` — 초기 뷰 (Rust 호출 포함)**

```swift
import SwiftUI

struct ContentView: View {
    // Rust에서 받아오는 초기 인사말. Phase 0 검증 지점.
    @State private var greeting: String = "Loading..."

    var body: some View {
        ZStack {
            // Theme B의 미니 프리뷰 — 방사형 컬러 그라디언트 + 다크 베이스
            LinearGradient(
                colors: [.teal.opacity(0.4), .indigo.opacity(0.5), .pink.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("🏔️")
                    .font(.system(size: 64))
                Text(greeting)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Phase 0 — Foundation")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(40)
        }
        .task {
            greeting = greet().toString()
        }
    }
}
```

주의: `greet()`는 Task 5에서 swift-bridge가 생성해 Task 6 스크립트가 `apps/Sources/Generated/cairn_ffi.swift`에 복사한 함수. Xcode가 그 파일을 소스로 포함시켜야 빌드된다 → 다음 단계에서 `project.yml`에 등록.

`.toString()`은 swift-bridge가 Rust `String`을 `RustString`으로 매핑하고 `.toString()`로 Swift String 변환하도록 생성하는 메서드.

- [x] **Step 4: `apps/Sources/BridgingHeader.h` — 브리지 헤더**

```c
#ifndef BridgingHeader_h
#define BridgingHeader_h

#import "Generated/cairn_ffi.h"

#endif /* BridgingHeader_h */
```

- [x] **Step 5: `apps/project.yml` — xcodegen 설정**

```yaml
name: Cairn
options:
  bundleIdPrefix: com.ongjin
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    ARCHS: "$(ARCHS_STANDARD)"  # arm64 + x86_64
    SWIFT_OBJC_BRIDGING_HEADER: Sources/BridgingHeader.h
    # Rust 유니버셜 static lib 링크
    LIBRARY_SEARCH_PATHS:
      - $(SRCROOT)/../target/universal/release
    OTHER_LDFLAGS:
      - -lcairn_ffi
    # swift-bridge는 C++ stdlib 심볼을 참조할 수 있어 명시적으로 추가
    CLANG_CXX_LIBRARY: "libc++"

targets:
  Cairn:
    type: application
    platform: macOS
    sources:
      - path: Sources
    info:
      path: Sources/Info.plist
      properties:
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 ongjin. MIT License."
    # Phase 0엔 샌드박스·entitlements 불필요. v1.0 가까워지면 추가.
```

- [x] **Step 6: xcodegen 실행**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
```

Expected: `✅ Created project at ...apps/Cairn.xcodeproj`

프로젝트 파일이 생성되지만 `.gitignore`에 의해 git에서 제외됨.

- [x] **Step 7: 커밋 (Swift 소스 + project.yml만)**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/project.yml apps/Sources/CairnApp.swift apps/Sources/ContentView.swift apps/Sources/BridgingHeader.h
git commit -m "feat(app): add minimal SwiftUI scaffold with xcodegen config"
```

---

## Task 8: Xcode 빌드 검증 (end-to-end)

지금까지 만든 Rust lib + Swift 앱을 실제로 연결해서 빌드 성공 + 실행 시 UI에 Rust 문자열이 떠야 한다.

- [x] **Step 1: 생성된 바인딩이 apps/Sources/Generated/에 있는지 재확인**

```bash
cd /Users/cyj/workspace/personal/cairn
ls apps/Sources/Generated/
```

Expected: `cairn_ffi.swift`, `cairn_ffi.h` (Task 6 Step 4에서 복사됨). 만약 비어있으면 `./scripts/gen-bindings.sh` 다시 실행.

- [x] **Step 2: 유니버셜 static lib 있는지 확인**

```bash
ls -lh target/universal/release/libcairn_ffi.a
```

Expected: 파일 존재. 수십 MB 크기.

- [x] **Step 3: Xcode 프로젝트 재생성 (Sources/Generated 추가된 상태 반영)**

```bash
cd apps
xcodegen generate
```

- [x] **Step 4: xcodebuild로 명령줄 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild -project Cairn.xcodeproj -scheme Cairn -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`

자주 발생하는 에러와 해결:
- `library 'cairn_ffi' not found` → `LIBRARY_SEARCH_PATHS` 경로가 틀렸거나 `scripts/build-rust.sh` 미실행.
- `cannot find 'greet' in scope` → `apps/Sources/Generated/` 비어있음. `./scripts/gen-bindings.sh` 재실행.
- `Bridging header ... not found` → `project.yml`의 `SWIFT_OBJC_BRIDGING_HEADER` 경로 확인.
- `SWIFT_BRIDGE_CORE ... undefined` → `swift-bridge` 버전에 따라 `SwiftBridgeCore.swift`/`.h`가 필요할 수 있음. `gen-bindings.sh`가 이미 복사하지만, 실제 경로는 `find target -name 'SwiftBridgeCore.*'`로 확인 가능.

- [x] **Step 5: 앱 실행해서 UI 확인**

```bash
# 빌드 산출 위치 찾기
APP=$(find apps/build -name "Cairn.app" -type d | head -1)
echo "$APP"
open "$APP"
```

Expected: SwiftUI 윈도우가 뜨고 화면 중앙에:
```
🏔️
Hello, Cairn! (from Rust)
Phase 0 — Foundation
```

이 문자열이 보이면 **Phase 0의 핵심 검증 성공** — Rust 엔진이 Swift UI로 데이터를 성공적으로 전달했다.

- [ ] **Step 6: 스크린샷 찍기 (나중에 README에 넣을 용도)** — skipped per user (manual)

```bash
# macOS 내장: ⌘⇧4 + space → 윈도우 클릭. 바탕화면에 저장됨.
# 또는 CLI로:
screencapture -l $(osascript -e 'tell app "Cairn" to id of window 1') ~/Desktop/cairn-phase-0.png 2>/dev/null || echo "Skipped (앱이 포커스 없을 수 있음)"
```

(실패해도 Phase 0 완료엔 무관. 수동으로 찍어서 README에 붙이면 됨.)

- [x] **Step 7: 커밋 불필요 — 이 태스크는 검증이 전부**

빌드 결과물(`apps/build/`, `apps/Cairn.xcodeproj/`)은 모두 gitignore.

---

## Task 9: GitHub Actions CI

Rust 테스트 + 유니버셜 빌드 + Xcode 빌드를 macos-latest 러너에서 전부 돌린다.

**Files:**
- Create: `.github/workflows/ci.yml`

- [x] **Step 1: `.github/workflows/ci.yml` 작성**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  rust:
    name: Rust — test & lint
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain (from rust-toolchain.toml)
        run: |
          rustup show          # reads rust-toolchain.toml and installs
          rustup target add aarch64-apple-darwin x86_64-apple-darwin

      - name: Cache cargo
        uses: Swatinem/rust-cache@v2

      - name: cargo fmt
        run: cargo fmt --all -- --check

      - name: cargo clippy
        run: cargo clippy --workspace --all-targets -- -D warnings

      - name: cargo test
        run: cargo test --workspace

  swift:
    name: Swift — build app
    runs-on: macos-latest
    needs: rust
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust toolchain
        run: |
          rustup show
          rustup target add aarch64-apple-darwin x86_64-apple-darwin

      - name: Cache cargo
        uses: Swatinem/rust-cache@v2

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Build Rust universal static lib
        run: ./scripts/build-rust.sh

      - name: Generate bindings
        run: ./scripts/gen-bindings.sh

      - name: Generate Xcode project
        working-directory: apps
        run: xcodegen generate

      - name: Build Cairn.app
        working-directory: apps
        run: |
          xcodebuild \
            -project Cairn.xcodeproj \
            -scheme Cairn \
            -configuration Debug \
            -destination "platform=macOS" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            build | xcbeautify --quiet
```

주의: `xcbeautify`가 없으면 파이프를 떼고 원시 출력으로 두어도 OK. 러너가 작아서 별도 설치 추가 없이도 동작.

- [x] **Step 2: 빌드 명령을 완화 (xcbeautify 없이도 동작)**

CI 마지막 xcodebuild 단계를 안전하게:

```yaml
      - name: Build Cairn.app
        working-directory: apps
        run: |
          set -o pipefail
          xcodebuild \
            -project Cairn.xcodeproj \
            -scheme Cairn \
            -configuration Debug \
            -destination "platform=macOS" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            build
```

- [x] **Step 3: 로컬에서 CI 시뮬레이션 (선택)**

```bash
cd /Users/cyj/workspace/personal/cairn
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
./scripts/build-rust.sh
./scripts/gen-bindings.sh
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build | tail -5)
```

Expected: 전부 성공. `cargo fmt`에서 diff 있으면 `cargo fmt --all` 실행 후 재시도.

- [x] **Step 4: 커밋 + push (CI 실제 실행 확인)**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for rust tests and xcode build"
```

- [ ] **Step 5: GitHub에 push (리모트 설정 안 돼있으면 추가)** — skipped per user (manual)

```bash
# 리모트 확인
git remote -v

# 없으면 추가 (리모트 저장소 먼저 GitHub에서 생성: https://github.com/new → name: cairn, empty)
# git remote add origin git@github.com:ongjin/cairn.git
# git push -u origin main
```

(리모트 생성 + push는 유저가 수동으로 해야 함. CI 트리거는 push 이후.)

- [ ] **Step 6: GitHub Actions 탭에서 녹색 확인** — pending user push

Expected: `rust` 잡 녹색, `swift` 잡 녹색. 총 7~10분 소요.

---

## Task 10: Phase 0 완료 체크 + 문서 업데이트

- [ ] **Step 1: README에 실제 스크린샷 (선택)** — skipped per user (manual)

Task 8 Step 6에서 찍은 스크린샷을 `docs/screenshots/phase-0.png`로 저장 후 README에 추가:

`README.md`의 `## Features` 위에 다음 블록 추가:

```markdown
## Current state

![Cairn Phase 0](./docs/screenshots/phase-0.png)

Phase 0 — Foundation. SwiftUI 앱이 Rust 엔진 호출 파이프라인을 통해 문자열을 받아 표시합니다.
```

```bash
mkdir -p docs/screenshots
# 스크린샷 파일을 docs/screenshots/phase-0.png로 이동
# (Task 8 Step 6에서 찍은 파일 경로에 따라 조정)
```

(스크린샷 없으면 이 단계 건너뛰어도 됨. v0.1 릴리스 때 꼭 넣기.)

- [x] **Step 2: 플랜 체크리스트 갱신**

이 플랜 파일(`docs/superpowers/plans/2026-04-21-cairn-phase-0-foundation.md`)의 각 태스크 `- [x]`를 `- [x]`로 마킹. 실행 스킬(executing-plans)이 자동으로 해주면 베스트.

- [x] **Step 3: 최종 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add -A
git commit -m "docs: add phase 0 screenshot and update README" --allow-empty
git log --oneline
```

Expected 최종 커밋 히스토리(근사):
```
feat(ci): add github actions workflow
feat(app): add minimal SwiftUI scaffold with xcodegen config
build: add rust universal build script and bindings copy script
feat(ffi): add swift-bridge scaffolding with greet() function
feat(crates): add skeleton crates for walker, search, preview, index
feat(core): add hello() skeleton with test
build(rust): add cargo workspace root and toolchain pin
docs: add README and MIT LICENSE
docs: initial design spec for Cairn v1.0
```

---

## 🎯 Phase 0 Definition of Done

다음을 모두 만족하면 Phase 0 완료:

- [x] `cargo test --workspace` 녹색
- [x] `cargo clippy --workspace -- -D warnings` 녹색
- [x] `./scripts/build-rust.sh` 성공, 유니버셜 static lib 생성됨
- [x] `./scripts/gen-bindings.sh` 성공, `apps/Sources/Generated/`에 `cairn_ffi.swift`, `cairn_ffi.h` 존재
- [x] `xcodegen generate`로 `apps/Cairn.xcodeproj` 생성
- [x] `xcodebuild -scheme Cairn -configuration Debug build` 성공
- [x] 앱 실행 시 `Hello, Cairn! (from Rust)` 표시됨
- [ ] GitHub Actions CI 녹색 (rust + swift 잡 둘 다) — pending user push
- [x] README가 빌드 방법을 정확히 설명하고, 설명대로 따라하면 위 전부 재현 가능

## 다음 플랜 (Phase 1 — FS Walking + 기본 UI)

Phase 0가 끝나면 다음 플랜을 별도로 작성:

- `cairn-walker` 크레이트 구현 (ignore + jwalk, 디렉터리 순회)
- 사이드바 (Pinned / Recent / Devices)
- 파일 리스트 뷰 (Name / Size / Modified / Kind)
- 기본 Theme B 구현 (NSVisualEffectView + 색상 토큰)
- 경로 breadcrumb + 백포워드
- `⌘↑` 상위 폴더, `⌘←→` 히스토리

목표 기간: 2개월.
