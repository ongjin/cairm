# Cairn Phase 1 · M1.7 — Design Polish (Design Spec)

**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md`
**Predecessor milestone:** M1.6 (tag `phase-1-m1.6` / `v0.1.0-alpha`) — search + polish + alpha release
**Date:** 2026-04-22
**Stance:** alpha 유저 feedback 반영 전에 디자인 파운데이션 마감. Phase 2 진입 전 "Finder-replacement 룩앤필" 을 M1.5 Glass Blue 기준으로 전 영역에 확장.

---

## 1. 목표

M1.5 에서 사이드바 / 프리뷰 / 윈도우 chrome 에 Glass Blue 를 적용했지만, **파일 리스트 (NSTableView) 와 인터랙션 표면** (selection, SearchField, focus) 은 macOS 기본값 그대로 남았다. 이 격차가 "디자인 안 한 것 같다" 는 유저 인상을 만듦. M1.7 는 **이미 정의된 `CairnTheme` 토큰을 전 영역에 일관 적용** + **Finder parity 필수 비주얼** (시스템 아이콘, empty state) 마감.

**알파 알파.1 로 릴리스 예정** (`v0.1.0-alpha.1` 태그). search 나 기능 추가는 없음.

---

## 2. 범위 (Locked)

### 2.1 들어가는 것

1. **파일 리스트 배경** — NSScrollView/NSTableView opaque background 제거 + `VisualEffectBlur(.contentBackground)` + `panelTint @ 0.55`
2. **파일 타입 아이콘** — `NSWorkspace.shared.icon(forFile:)` 로 실제 시스템 아이콘 사용. 확장자 단위 `NSCache` (메모리 bound)
3. **Empty states** — 3 케이스 공통 `EmptyStateView`: 빈 폴더 / 검색 no-match / 권한 없음
4. **Selection / Focus / SearchField** — `CairnTheme.accentMuted` 를 세 표면 모두에 일관 적용
5. **애니메이션** — search batch populate fade-in (150ms), 정렬 전환은 기존 AppKit row-anim 유지, empty state crossfade (200ms). `accessibilityReduceMotion` 존중
6. **다크/라이트 검증** — 현재 Glass Blue 는 dark-first. `NSAppearance.current.bestMatch(from:)` 로 라이트 모드에서도 텍스트 컨트라스트 ≥ 4.5:1 보장
7. **키 포커스 링** — macOS HIG 시스템 링 유지 (변경 안 함). 단, SearchField + custom row selection 이 키 focus 를 막지 않게 확인

### 2.2 들어가지 않는 것 (Phase 2 +)

- 테마 스위처 (다크/라이트/Glass/Arc 등 — 스펙 원문 § 11.3 Phase 3)
- 드래그 앤 드롭 (파일 이동 / 붙여넣기)
- 다국어 (i18n)
- 커스텀 키바인딩 설정 UI
- 파일 preview 뷰 애니메이션 (transitions between .text/.image/.directory)
- 검색 결과 정렬-by-relevance (M1.7 는 name/size/modified 만)
- 아이콘 커스텀 테마팩

---

## 3. 아키텍처

### 3.1 레이어 다이어그램

```
┌────────────────────── macOS app ─────────────────────────┐
│                                                            │
│  CairnTheme (M1.5 정의)  — 토큰 재사용만                    │
│    ├─ accentMuted (#0A84FF @ 22%)                         │
│    ├─ panelTint (Glass Blue @ 0.55)                       │
│    └─ bodyFont / headerFont / cornerRadius                │
│                                                            │
│  신규 컴포넌트                                              │
│    ├─ EmptyStateView            (SwiftUI, 범용)           │
│    ├─ ThemedSearchField         (SwiftUI, 기존 SearchField 대체) │
│    └─ FileListIconCache         (NSCache<NSString, NSImage>) │
│                                                            │
│  수정 컴포넌트                                              │
│    ├─ FileListView              (scrollContentBackground + bg blur) │
│    ├─ FileListCoordinator       (icon cache + custom row selection) │
│    ├─ FileListNSTableView       (row view override)        │
│    ├─ ContentView               (empty state 분기 + ThemedSearchField) │
│    └─ SearchField               (ThemedSearchField 로 리네임/교체) │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 3.2 핵심 설계 선택

- **토큰 재사용** — `CairnTheme` 에 새 토큰 추가 없음. M1.5 `.glass` 그대로.
- **Icon cache lifecycle** — 앱 실행 동안 유지 (일반 유저 세션 내 얻는 퍼포먼스 이득 > 메모리 비용). `FileListCoordinator.attach(table:)` 에서 기존 cache 유지 (폴더 전환마다 초기화 X — ext 는 폴더 불변).
- **Custom NSTableRowView** — `NSTableView` selection 은 기본이 system accent solid 파랑. `accentMuted` 22% 를 쓰려면 `NSTableRowView` subclass + `drawSelection(in:)` override 가 최소침습 방식. 전체 row custom delegate 교체는 overkill.
- **SearchField 리네임** — M1.6 의 `SearchField.swift` 를 `ThemedSearchField.swift` 로 교체. 파일 단위 rename 을 명시해서 diff 가 혼란스럽지 않게.
- **Empty state 위치** — `FileListView` 내부가 아닌 `ContentView.contentColumn` 에서 entries count / search state 기반 분기. NSViewRepresentable 안에 분기 로직 넣으면 SwiftUI state 재생성 비용 ↑.

---

## 4. Swift 구현 경계

### 4.1 신규 파일

- `apps/Sources/Views/Empty/EmptyStateView.swift` — icon + title + optional subtitle + optional action button. 3 factory method (`.emptyFolder`, `.searchNoMatch(query:)`, `.permissionDenied(onRetry:)`)
- `apps/Sources/Views/Search/ThemedSearchField.swift` — 기존 `SearchField.swift` 대체. M1.6 로직 그대로 + theme-tinted background + accent border
- `apps/Sources/Services/FileListIconCache.swift` — `NSCache` 래퍼. `icon(forPath:)` / `icon(forDirectory:)` 두 entry point
- `apps/Sources/Views/FileList/FileListRowView.swift` — `NSTableRowView` subclass, `drawSelection(in:)` override

### 4.2 수정 파일

- `apps/Sources/Views/FileList/FileListView.swift` — `NSScrollView.drawsBackground = false`, NSTableView 도 동일. 외곽에 `.background { VisualEffectBlur(.contentBackground); theme.panelTint.opacity(0.55) }.ignoresSafeArea()`
- `apps/Sources/Views/FileList/FileListCoordinator.swift` — `systemImage(for:)` 를 `FileListIconCache` 호출로 교체. `tableView(_:rowViewForRow:)` delegate 메서드 추가해서 `FileListRowView` 반환
- `apps/Sources/ContentView.swift` — `emptySearchState` 에서 `EmptyStateView.searchNoMatch(query:)` 사용. 빈 폴더 분기 추가 (`folder.state == .loaded && folder.entries.isEmpty`). 권한 에러 분기 (`folder.state == .failed(...)` 에서 `EmptyStateView.permissionDenied`)
- `apps/Sources/Views/Search/SearchField.swift` — 삭제. `ThemedSearchField.swift` 로 교체 (파일 삭제 + 신규)

### 4.3 Touch 없음 (의도적)

- `CairnTheme.swift` — 토큰 추가 없음
- `VisualEffectBlur.swift` — 그대로
- `SidebarView.swift` — M1.5 대로
- `PreviewPaneView.swift` — M1.5 대로 (프리뷰 panel tint 이미 M1.5 에서 처리됨)
- `SearchModel.swift` / `FolderModel.swift` — 로직 불변
- 모든 Rust 크레이트 — M1.7 는 Swift-only

---

## 5. 컴포넌트 상세

### 5.1 `EmptyStateView`

```swift
struct EmptyStateView: View {
    let icon: String       // SF Symbol 이름
    let title: String
    let subtitle: String?
    let action: Action?

    struct Action {
        let label: String
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(title).font(theme.bodyFont.weight(.medium))
            if let subtitle { Text(subtitle).font(theme.headerFont).foregroundStyle(.tertiary) }
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    static func emptyFolder() -> EmptyStateView {
        .init(icon: "folder", title: "Empty folder", subtitle: "No files here.", action: nil)
    }
    static func searchNoMatch(query: String) -> EmptyStateView {
        .init(icon: "magnifyingglass", title: "No matches", subtitle: "for \"\(query)\"", action: nil)
    }
    static func permissionDenied(onRetry: @escaping () -> Void) -> EmptyStateView {
        .init(icon: "lock", title: "Can't read this folder",
              subtitle: "The system denied access.",
              action: .init(label: "Grant Access…", perform: onRetry))
    }
}
```

### 5.2 `ThemedSearchField`

M1.6 `SearchField` 의 모든 state binding 유지. 변경은 단일 block — `TextField` 의 styling:

```swift
TextField("Search", text: $search.query)
    .textFieldStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
        RoundedRectangle(cornerRadius: theme.cornerRadius)
            .fill(theme.accentMuted.opacity(0.3))
    )
    .overlay(
        RoundedRectangle(cornerRadius: theme.cornerRadius)
            .stroke(theme.accent.opacity(0.4), lineWidth: 1)
    )
    .focused($focused)
    .frame(width: 200)
```

### 5.3 `FileListIconCache`

```swift
final class FileListIconCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 500   // 확장자 단위 — 전형적 세션이면 50 개 미만
    }

    /// 파일 확장자를 키로 lookup. `NSWorkspace.icon(forFile:)` 은 실 파일 경로를 필요로 하지만
    /// 같은 확장자는 같은 아이콘을 반환하므로 확장자 단위 캐시 안전.
    /// Directory 는 별도 entry (key = "__dir__").
    func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let key: NSString
        if isDirectory {
            key = "__dir__"
        } else {
            key = NSString(string: (path as NSString).pathExtension.lowercased())
        }
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(img, forKey: key)
        return img
    }
}
```

Coordinator 에서:
```swift
private let iconCache = FileListIconCache()

private func systemImage(for entry: FileEntry) -> NSImage {
    iconCache.icon(forPath: entry.path.toString(), isDirectory: entry.kind == .Directory)
}
```

### 5.4 `FileListRowView`

```swift
final class FileListRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        // Use system accent so User > System > Appearance > Accent color 설정이 반영됨.
        // alpha 값 0.22 는 CairnTheme.accentMuted 와 같은 값.
        let color = NSColor.controlAccentColor.withAlphaComponent(0.22)
        color.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0),
                                xRadius: 4, yRadius: 4)
        path.fill()
    }
}
```

`FileListCoordinator` 에서:
```swift
func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    FileListRowView()
}
```

### 5.5 `FileListView` 배경

기존 `makeNSView` 끝 부분에 NSScrollView + NSTableView background 끄기:

```swift
scroll.drawsBackground = false
table.backgroundColor = .clear
table.usesAlternatingRowBackgroundColors = false  // Glass 위에서 alt 색 깨짐
```

SwiftUI level 에서:
```swift
.background {
    ZStack {
        VisualEffectBlur(material: .contentBackground)
        theme.panelTint.opacity(0.55)
    }
    .ignoresSafeArea()
}
```

### 5.6 `ContentView` empty state 분기

기존 `contentColumn` 확장:
```swift
@ViewBuilder
private var contentColumn: some View {
    if let folder, let searchModel {
        VStack(spacing: 0) {
            cappedBanner
            if searchModel.isActive && searchModel.results.isEmpty && searchModel.phase != .running {
                EmptyStateView.searchNoMatch(query: searchModel.query)
            } else if !searchModel.isActive && folder.state == .loaded && folder.entries.isEmpty {
                EmptyStateView.emptyFolder()
            } else if case .failed = folder.state, !searchModel.isActive {
                EmptyStateView.permissionDenied { requestReopen() }
            } else {
                fileList(folder: folder, searchModel: searchModel)
            }
        }
    } else {
        ProgressView().controlSize(.small)
    }
}

private func requestReopen() {
    // NSOpenPanel 을 다시 띄워 유저가 권한 재부여
    // 구현은 AppModel.reopenCurrentFolder() 를 새로 만들어서 delegate
}
```

---

## 6. 애니메이션 가이드

**타이밍 토큰** (CairnTheme 에 추가하지 않음 — M1.7 inline 상수로 충분. Phase 2 에서 토큰화):

| Token | 값 | 용처 |
|---|---|---|
| `fast` | 0.15s | Empty state crossfade, search result fade-in |
| `medium` | 0.2s | Picker scope transition, capped banner appear/disappear |
| `slow` | 0.3s | None (M1.7 엔 필요 없음) |

**구현 원칙**
- SwiftUI `.transition(.opacity.animation(...))` 또는 `withAnimation(.easeOut(duration:))`
- `@Environment(\.accessibilityReduceMotion)` 존재 시 전부 `withAnimation(nil)` 로 우회
- AppKit row 애니메이션은 `tableView.beginUpdates` / `endUpdates` 자체 기본 유지 (M1.2 에서 세팅됨)

**애니메이션 추가 지점**
- `searchModel.results.append(contentsOf: batch)` — SwiftUI 쪽이 아닌 NSTableView 라 SwiftUI animation 비해당. NSTableView 의 `noteNumberOfRowsChanged()` 가 default fade 를 씀 — 그대로 두고 별도 애니메이션 없음. (M1.7 는 여기 건드리지 않음)
- Empty state 교체 — `VStack` 에 `.animation(.easeInOut(duration: 0.2), value: stateKey)` 붙이기
- Capped banner 등장/퇴장 — `.transition(.move(edge: .top).combined(with: .opacity))`

---

## 7. 수동 E2E 체크리스트 (parent spec § 9 addendum)

**M1.7 신규**
- [ ] 루트 폴더 윈도우: 파일 리스트 영역이 사이드바 / 프리뷰와 같은 Glass Blue 톤으로 보임 (단절 없음)
- [ ] 파일 각각이 macOS 시스템 아이콘 표시 (Xcode / Music / Mail 파일은 해당 앱 아이콘, .md 는 generic 문서 아이콘)
- [ ] 아이콘 캐시 동작: 1,000 개 파일 폴더 첫 로드 vs 재방문 — 재방문이 체감상 즉시
- [ ] 빈 폴더 진입 → "Empty folder" + folder SF Symbol
- [ ] `⌘F` → 매치 없는 쿼리 입력 → "No matches for ...." state
- [ ] 권한 없는 폴더 클릭 → "Can't read this folder" + "Grant Access..." 버튼 → NSOpenPanel 재프롬프트
- [ ] SearchField: default white box 아니라 accent-tinted rounded rect 보임, focus 시 accent border 강조
- [ ] 파일 선택: system 파랑 solid 가 아닌 accentMuted 22% pill
- [ ] 사이드바 hover pill ↔ 파일리스트 selection ↔ SearchField — 셋 다 같은 파랑 톤
- [ ] 라이트 모드 전환 (System Settings → Appearance → Light) → 텍스트 읽을 수 있음 (WCAG AA 4.5:1)
- [ ] `accessibilityReduceMotion` ON (System Settings) → empty state 전환 즉시 (fade 없음)

**M1.6 regression 확인**
- [ ] `⌘F` / scope toggle / subtree streaming / `⌘⌫` Trash / Open With cache 모두 정상

---

## 8. 테스트 전략

**XCTest 추가** (최소):
- `EmptyStateViewTests.swift` — factory method 각각이 올바른 icon / title 생성 (body 렌더링 X — visual 테스트는 XCTest 부적합)
- `FileListIconCacheTests.swift` — 같은 확장자 두 번째 호출 시 cache hit. 실 `NSWorkspace.icon(forFile:)` 호출 여부를 mock 하긴 어려우므로, cache instance 가 두 번 호출 후 `cache.object(forKey:)` 로 같은 NSImage 참조를 반환하는지만 확인 (identity check via `===`)

**시각 회귀**: parent spec § 10 policy 에 따라 Phase 2 이후 (Phase 1 은 수동 E2E)

---

## 9. 리스크 & 완화

| 리스크 | 완화 |
|---|---|
| `NSWorkspace.icon(forFile:)` 가 큰 폴더 첫 로드에서 UI jank | ext 단위 캐시 (500 entry) + NSImage 자체는 ~4KB 이라 1MB 미만 메모리. 첫 로드 ext 다양성이 50 개 넘는 폴더는 현실적으로 드뭄 |
| `NSTableRowView.drawSelection(in:)` 이 darkmode/lightmode 따라 빗나갈 수 있음 | 고정 RGBA 대신 `NSColor.controlAccentColor.withAlphaComponent(0.22)` 사용 — 시스템이 모드 따라 자동 조정. `accentMuted` 토큰도 같이 업데이트 고려 |
| `VisualEffectBlur(.contentBackground)` + `panelTint` 이중 오버레이가 너무 어두워질 수 있음 | 현재 M1.5 가 이미 프리뷰 패널에 같은 구성 — 시각 확인됨. 파일 리스트도 동일 재사용 |
| 라이트 모드에서 글자 컨트라스트 부족 | CairnTheme 에 라이트/다크 variant 추가 대신, `NSAppearance` 감지해서 `text` 토큰만 런타임 교체. 구현 세부 Task 에서 결정 |
| 기존 SearchField 파일 삭제 + 신규 파일 추가가 xcodegen 에서 꼬임 | xcodegen 은 파일 시스템 기반이라 자동 해결. `*.xcodeproj` diff 만 확인 |
| 다중 테마 (Phase 3) 때문에 `accentMuted` hardcode 가 발목 | Phase 3 에서 `CairnTheme.current` 로 런타임 스위칭 시 `FileListRowView.drawSelection` 도 theme-aware 화 필요. 지금은 single theme 이라 무시 |

---

## 10. 마일스톤 & Tag

- M1.7 완료 + 수동 E2E 통과 시 `git tag phase-1-m1.7`
- 릴리스는 `v0.1.0-alpha.1` 로 (alpha 아직 유지, 버그픽스/디자인 폴리시 성격)
- Phase 2 진입은 M1.7 tag 후

---

*이 문서는 `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` 의 구체 확장이다. 구현 플랜은 `docs/superpowers/plans/YYYY-MM-DD-cairn-phase-1-m1.7-design-polish.md` 로 별도 작성 (superpowers:writing-plans).*
