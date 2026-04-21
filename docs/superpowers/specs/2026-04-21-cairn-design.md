# Cairn — Design Spec

**Date:** 2026-04-21
**Author:** ongjin
**Status:** Draft (브레인스토밍 결과, v1.0 플래닝 인풋)

---

## 1. 한 줄 설명

**Cairn** — macOS에서 가장 아름다운 오픈소스 파일 매니저. 개발자용 속도, 디자이너급 마감.

## 2. 문제 정의

macOS 파일 매니저 시장은 양극화돼 있다:

- **Finder**: 이쁜 편이지만 기능 빈약, 업데이트 정체
- **Forklift / Path Finder / Commander One**: 기능은 많지만 AppKit 올드 룩. 유료
- **Yazi / broot / lf / nnn**: 빠르고 강력하지만 TUI
- **빈 공간**: Sonoma/Sequoia급 비주얼 완성도 + ripgrep급 성능 + ⌘K 파워유저 UX를 모두 가진 앱

Cairn은 이 빈 공간을 차지한다.

## 3. 타겟 사용자

- macOS 사용 개발자
- 키보드 파워유저 (Raycast / Arc / Zed 같은 툴 애호)
- 비주얼 완성도에 민감한 디자이너·프론트엔드 엔지니어

## 4. Non-Goals (영구적으로 안 할 것)

- Windows / Linux 포팅 — 포지션이 희석됨. macOS 전용이 차별점.
- 완전한 시스템 Finder 교체 — 공식 API가 없음. "체감 대체"까지만.
- GUI로 감싼 Nautilus/Explorer 클론 — 그건 이미 Forklift가 있다.
- 유료화 — 오픈소스 유지. 스폰서·기부만.

## 5. 핵심 결정 (Locked)

| 항목 | 결정 |
|---|---|
| 플랫폼 | macOS only |
| UI 스택 | SwiftUI + AppKit (필요시) |
| 엔진 스택 | Rust |
| 바인딩 | `swift-bridge` |
| 기본 테마 | B · Glass / macOS++ |
| 선택 테마 | A · Arc/Linear, C · Raycast |
| 주요 인터랙션 | ⌘K 커맨드 팔레트 (비-모달) |
| Finder 관계 (v1.0) | 공존형 (coexist) |
| Finder 관계 (장기) | 체감 대체 (Finder Sync Extension, 로그인 상주 등) |
| 라이선스 | MIT (잠정) |

## 6. MVP 스코프 (v1.0)

**v1.0은 3개 기능을 미친 완성도로.**

### 6.1 멀티 테마 시스템
- B (Glass) 기본, A (Arc) / C (Raycast) 선택
- 런타임 전환 + 200ms cross-fade
- 테마는 단순 컬러가 아님 — **레이아웃 variant 포함**
  - A, B: three-pane (사이드바 · 메인 · 프리뷰)
  - C: palette-first (팔레트가 영구 노출, 메인 UI가 그 연장)

### 6.2 ⌘K Command Palette

단일 입력으로 **파일 이동 + 액션 실행 + 딥 서치**를 모두 처리.

**결과 구역 (타이핑마다 재정렬):**
1. Files — Current Folder (fuzzy)
2. Files — Recent
3. Pinned 매칭
4. Actions (네비/ops/toggle)
5. "Search everywhere" — `⌘↵` 유도

**액션 레지스트리 (v1.0):**
- Navigate: Home / Desktop / Workspace / 직전 폴더 / back / forward
- File ops: Copy path, Reveal in Finder, Open in Terminal, Open in VSCode/Cursor
- View: Tree↔List 토글, Preview pane 토글, Theme 전환
- Search: This folder / Everywhere / By name / By content

### 6.3 ⚡ Lightning Search

**두 모드:**
- **Inline** (`⌘K` 타이핑): 현재 폴더 한정, <10ms 응답
- **Deep** (`⌘↵` 또는 `⌘⇧K`): 인덱싱된 루트 전역

**인덱싱:**
- 기본 Indexed roots: `~/workspace`, `~/Desktop`, `~/Documents`
- 첫 시작 시 백그라운드 크롤 + 이후 FSEvents 증분
- `.gitignore` 존중 + 하드코딩 제외 목록 (`node_modules`, `.git`, `target`, `.next`, `build`, `dist` 등)
- 캐시: `~/Library/Application Support/Cairn/index.db` (redb)

## 7. v1.0에 안 들어가는 것 (로드맵)

| 기능 | 대상 릴리스 |
|---|---|
| Git status 오버레이 | v1.1 |
| Finder Sync Extension (우클릭 "Open in Cairn") | v1.1 |
| 글로벌 단축키 (`⌥⌘Space` 소환) | v1.1 |
| 대량 리네임 / 배치 작업 | v1.2 |
| 태그·북마크 시스템 | v1.2 |
| 클라우드 (iCloud/Dropbox/GDrive) 통합 뷰 | v2.0 |
| 플러그인 시스템 | v2.0 |
| 커뮤니티 테마 TOML | v2.0 |
| "Quit Finder on launch" 옵션 | v2.0 |
| 외장 디스크 자동 열기 가로채기 | v2.0 |

## 8. 키보드 단축키 (v1.0)

| 키 | 동작 |
|---|---|
| `↑↓` | 파일 이동 |
| `←→` | 상위/하위 폴더 |
| `↵` | 열기 |
| `⌘K` | 팔레트 |
| `⌘⇧K` | Deep 서치 직행 |
| `⌘1 / 2 / 3` | 사이드바 / 메인 / 프리뷰 포커스·토글 |
| `⌘,` | 설정 |
| `⌘N` | 새 윈도우 |
| `⌘T` | 터미널 열기 (현재 폴더) |
| `⌘E` | 에디터 열기 |
| `Space` | Quick Look (macOS 네이티브) |
| `⌘⌫` | 휴지통 |
| `/` | 현재 폴더 내 검색 포커스 |

모든 단축키는 Settings에서 재정의 가능. Profile별 다른 바인딩 셋 가능 (예: "Vim 모드" 프리셋을 v1.1+에서 제공).

## 9. 아키텍처

### 9.1 상위 구조

```
┌───────────────────────────────────┐
│  SwiftUI 앱 (UI 레이어)           │
│  - 뷰, 상태, 테마 (B/A/C)         │
│  - 키보드 핸들링, 애니메이션      │
│  - Quick Look, macOS 네이티브 통합│
└───────────────┬───────────────────┘
                │  swift-bridge FFI
┌───────────────▼───────────────────┐
│  Rust 코어 (엔진)                 │
│  - 파일 워킹 (ignore/jwalk)       │
│  - 검색 (ripgrep 내부 크레이트)   │
│  - 프리뷰/syntax (tree-sitter)    │
│  - 인덱스 캐시 (redb)             │
└───────────────────────────────────┘
```

### 9.2 Monorepo 레이아웃

```
cairn/
├── apps/
│   └── Cairn.xcodeproj/
│       └── Cairn/
│           ├── App/                  # @main, AppDelegate, 윈도우
│           ├── Views/
│           │   ├── Sidebar/
│           │   ├── FileList/
│           │   ├── Preview/
│           │   └── Palette/
│           ├── ViewModels/           # @Observable 상태
│           ├── Theme/                # 테마 토큰 + 엔진
│           ├── Keyboard/             # 단축키 레지스트리
│           └── Services/
│               └── CairnEngine.swift # Rust FFI 래퍼
├── crates/
│   ├── cairn-core/                   # 퍼사드 / 공개 API
│   ├── cairn-walker/                 # fs 워킹 (ignore + jwalk)
│   ├── cairn-search/                 # 검색 (grep-*)
│   ├── cairn-preview/                # 프리뷰 + syntax
│   ├── cairn-index/                  # 인덱스 캐시
│   └── cairn-ffi/                    # swift-bridge — Swift 유일 접점
├── scripts/
│   ├── build-rust.sh
│   └── gen-bindings.sh
├── .github/workflows/ci.yml
├── Cargo.toml
└── README.md
```

### 9.3 Rust 크레이트 책임

| 크레이트 | 책임 | 주요 의존성 |
|---|---|---|
| `cairn-walker` | 디렉터리 순회, .gitignore, 메타데이터 | `ignore`, `jwalk` |
| `cairn-search` | 파일명 fuzzy + 내용 regex/literal | `grep-regex`, `grep-searcher` |
| `cairn-preview` | Syntax highlight, 썸네일, JSON/CSV | `tree-sitter`, `image` |
| `cairn-index` | 증분 인덱스 캐시 | `redb` |
| `cairn-core` | 오케스트레이션, 상위 공개 API | 위 전부 |
| `cairn-ffi` | swift-bridge 정의 | `swift-bridge` |

### 9.4 FFI 경계 설계

**원칙 3개:**

1. **Narrow boundary** — 함수 개수 최소화. 데이터는 struct로 한 번에 주고받기.
2. **Rust는 상태 없음, Swift가 UI 상태 소유** — Rust는 "입력 → 결과" 함수들의 모음. SwiftUI `@Observable` 상태는 Swift에서만.
3. **비동기는 Swift 콜백** — Rust 장기 연산은 Swift 쪽 `AsyncStream`으로 연결. FSEvents 알림도 같은 방식.

**초기 FFI 스케치:**

```rust
// crates/cairn-ffi/src/lib.rs
#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct FileEntry {
        path: String,
        name: String,
        size: u64,
        modified_unix: i64,
        kind: FileKind,
        is_hidden: bool,
    }

    enum FileKind { Directory, Regular, Symlink }

    #[swift_bridge(swift_repr = "struct")]
    struct SearchHit {
        path: String,
        line: Option<u32>,
        snippet: Option<String>,
        score: f32,
    }

    enum SearchScope { CurrentFolder, AllRoots }

    extern "Rust" {
        type Engine;

        fn new_engine(indexed_roots: Vec<String>) -> Engine;
        fn list_directory(&self, path: String) -> Vec<FileEntry>;
        fn search(&self, query: String, scope: SearchScope, limit: u32) -> Vec<SearchHit>;
        fn preview(&self, path: String, max_bytes: u64) -> String; // syntax-highlighted HTML
        fn subscribe_changes(&self, path: String, callback: /* Swift closure */);
    }
}
```

### 9.5 Swift 쪽 래퍼

```swift
// Services/CairnEngine.swift
@Observable
final class CairnEngine {
    private let rust: Engine

    init(indexedRoots: [URL]) {
        self.rust = new_engine(indexedRoots.map { $0.path })
    }

    func listDirectory(_ url: URL) async -> [FileEntry] {
        await Task.detached { [rust] in rust.list_directory(url.path) }.value
    }

    // ... Search, preview, subscribe
}
```

**금지:** Swift `@Observable` 상태를 FFI 넘기지 말 것. Rust는 plain data만 반환, Swift 뷰모델이 받아서 publish.

## 10. 테마 시스템

### 10.1 디자인 토큰

```swift
struct CairnTheme: Identifiable {
    let id: String                          // "glass", "arc", "raycast"
    let displayName: String

    // Colors
    let windowBackground: BackgroundStyle
    let panelBackground: Color
    let panelBlurRadius: CGFloat
    let text: Color
    let textSecondary: Color
    let accent: Color
    let selection: Color

    // Geometry
    let cornerRadius: CGFloat
    let panelPadding: EdgeInsets

    // Layout variant
    let layout: LayoutVariant

    // Typography
    let bodyFont: Font
    let monoFont: Font
}

enum LayoutVariant {
    case threePane       // A, B
    case paletteFirst    // C
}

enum BackgroundStyle {
    case gradient([Color])
    case visualEffect(NSVisualEffectView.Material)
    case solid(Color)
}
```

### 10.2 레이아웃 Variant

- `threePane`: 사이드바 · 메인 · 프리뷰 (토글 가능). Theme A, B.
- `paletteFirst`: 상단 팔레트 영구 노출. 메인 UI가 팔레트 결과 스트림의 연장선. Theme C.

**중요**: 뷰 구조는 variant별로 다르되, **뷰모델은 동일**. 같은 데이터를 다른 레이아웃으로 렌더할 뿐.

### 10.3 저장·전환

- `UserDefaults`: `com.ongjin.cairn.theme` (기본 `glass`)
- 설정 화면: 각 테마 큰 카드 (실제 미니 렌더)
- 런타임 전환 시 200ms `withAnimation` cross-fade

## 11. 빌드 & 배포

### 11.1 빌드 파이프라인

```bash
scripts/build-rust.sh        # Rust universal static lib (arm64 + x86_64)
scripts/gen-bindings.sh      # swift-bridge 바인딩 생성
xcodebuild -scheme Cairn -configuration Release
```

### 11.2 CI (GitHub Actions, `macos-latest`)

- `cargo test`, `cargo clippy -- -D warnings`
- `xcodebuild test` + SwiftLint
- 유니버셜 바이너리 빌드 (Intel Mac 지원)

### 11.3 배포 채널

- **DMG** — `create-dmg`
- **Homebrew cask** — `brew install --cask cairn` (v0.9 베타부터)
- **GitHub Releases** — 직접 다운로드
- **Notarization** — Developer ID 필수 ($99/yr)
- **Auto-update** — Sparkle + EdDSA 서명

### 11.4 버전 관리

- SemVer. v1.0 이전: `0.9.0-beta1` 등.
- 모든 릴리스: 스크린샷 + 30초 데모 영상.

## 12. 타임라인 추정

Rust 프로덕션 경험 있음, Swift 러닝커브 있음 가정.

| Phase | 기간 | 내용 |
|---|---|---|
| 0 | 1개월 | 아키텍처 세팅, swift-bridge hello-world, Xcode 프로젝트, CI |
| 1 | 2개월 | FS 워킹 + 기본 리스트 뷰 + 사이드바 (Theme B만) |
| 2 | 2개월 | ⌘K 팔레트 + 인라인 검색 + Deep 서치 + 인덱스 |
| 3 | 1.5개월 | Theme A, C 구현 + 테마 전환 + layout variant |
| 4 | 1개월 | 키보드 단축키 완성, Quick Look, 프리뷰 |
| 5 | 0.5개월 | 다듬기, 버그 수정, 데모 영상, v1.0 릴리스 |
| **합** | **8개월** | Swift 처음이면 +2달 여유 |

v1.1 (Git 상태, Finder Sync Extension, 글로벌 단축키): +2~3개월

## 13. 리스크 & 오픈 이슈

### 13.1 기술 리스크

| 리스크 | 완화 |
|---|---|
| Swift 러닝커브 지연 | Phase 0/1에서 단순 뷰부터. 복잡한 SwiftUI 패턴은 Phase 3부터 |
| `swift-bridge` 기능 미흡 | 폴백: 수동 C FFI (`cbindgen` + Bridging header) |
| NSVisualEffectView macOS 버전별 차이 | minimum macOS 13(Ventura)+로 제한 — 블러 품질 확보 |
| 인덱스 크기 폭증 | 제외 목록 엄격 + 루트당 상한 (`MAX_INDEXED_FILES=500_000`) |
| FSEvents 유실 | 주기적 전체 재검증 (매일 백그라운드 1회) |

### 13.2 오픈 이슈 (다음 단계에서 결정)

- [ ] Swift 경험 수준 미확인 — 실제 빌드 시작 전 "swift-bridge + SwiftUI hello world"로 Phase 0 스파이크 권장
- [ ] Intel Mac 지원 끊을지 여부 (arm64-only 빌드면 바이너리 크기/CI 시간 절반)
- [ ] macOS 최소 버전 최종 결정 (권장 13 Ventura)
- [ ] 네이밍 `Cairn` 최종 여부 (코드네임으로 쓰고 출시 전 재심의 가능)
- [ ] 도메인 `cairn.app` / GitHub 조직 생성

## 14. 성공 기준 (v1.0 런칭)

- [ ] HN Show HN 상위 10위 안
- [ ] GitHub 1k star (6개월 내)
- [ ] Twitter/Threads에서 "macOS에서 제일 이쁜 파일 매니저" 멘션 자생적 발생
- [ ] 데일리 액티브 유저 500+ (텔레메트리 opt-in)
- [ ] 크래시-프리 세션 99%+

## 15. 부록: 시각 목업 참조

브레인스토밍 시각 세션에서 작성된 목업:

- `visual-direction.html` — 4가지 테마 방향성 (선정: B, A, C)
- `main-layout.html` — Theme B 풀 레이아웃 + 팔레트 열린 상태, Theme A/C 변형
- 위치: `.superpowers/brainstorm/*/content/` (세션 종료 시 보존)

목업 자산은 v1.0 설계 시 아이콘·색·간격의 1차 기준.

---

*이 문서는 구현 플랜 (writing-plans 스킬 출력)의 입력이다. 플랜에서 Phase별 상세 작업이 쪼개진다.*
