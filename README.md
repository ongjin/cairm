# Cairn

Finder-replacement 을 지향하는 macOS 파일 브라우저. Rust 백엔드 (`cairn-walker` / `cairn-preview` / `cairn-search`) + SwiftUI 프론트엔드 (`NSTableView` bridge + `NSVisualEffectView` Glass Blue 테마).

**상태:** `v0.1.0-alpha` (Phase 1 완료). Phase 2 는 persistent index + content search + `⌘K` command palette + fuzzy match 예정.

## 빌드 (from source)

**요구사항**
- macOS 14 이상
- Rust 1.85 이상
- Xcode 15 (Swift 5.9) 이상
- 개발 도구: `xcodegen`, (선택) `create-dmg`

```bash
git clone https://github.com/ongjin/cairn.git
cd cairn
./scripts/build-rust.sh        # universal static lib
./scripts/gen-bindings.sh      # Swift bindings
(cd apps && xcodegen generate && xcodebuild -scheme Cairn -configuration Debug build \
    CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
open ~/Library/Developer/Xcode/DerivedData/Cairn-*/Build/Products/Debug/Cairn.app
```

Alpha DMG 는 `./scripts/make-dmg.sh` (서명 없음 — Gatekeeper 는 우클릭 → Open 으로 우회).

## 주요 키보드 단축키

| 키 | 동작 |
|---|---|
| `⌘↑` | 상위 폴더 |
| `⌘←` / `⌘→` | 히스토리 back / forward |
| `⌘⇧.` | 숨김 파일 토글 |
| `⌘D` | 현재 폴더 Pinned 추가 / 해제 |
| `⌘R` | 현재 폴더 리로드 |
| `⌘F` | 검색 필드 focus (This Folder / Subtree) |
| `Space` | Quick Look |
| `⌥⌘C` | 경로 복사 |
| `⌘⌫` | Move to Trash |

상세 사용법은 [`USAGE.md`](./USAGE.md).

## 로드맵

- **Phase 1 (완료)** — Rust walker + SwiftUI 리스트 + Pinned/Recent/iCloud/Locations 사이드바 + Preview (text/image/directory/binary) + Quick Look + Glass Blue 테마 + 컨텍스트 메뉴 (Reveal / Copy Path / Open With / Trash) + `⌘F` 검색 (folder / subtree)
- **Phase 2** — `cairn-index` (redb persistent) + FSEvents 실시간 동기화 + `⌘K` command palette + content search + fuzzy match
- **Phase 3** — 테마 스위처 + 다국어 + 배포 (서명/notarize)

설계 문서: [`docs/superpowers/specs/`](./docs/superpowers/specs/). 구현 플랜: [`docs/superpowers/plans/`](./docs/superpowers/plans/).

## 라이선스

MIT — see [LICENSE](./LICENSE).
