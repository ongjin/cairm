# Cairn Phase 1 · M1.5 — Glass Blue Theme + Context Menu + Sidebar Highlight + `⌘R`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Theme B Glass Blue 를 `CairnTheme` 토큰 + `NSVisualEffectView` 로 도입하고, 컨텍스트 메뉴를 **Copy Path / Move to Trash / Open With** 3 개로 확장, 사이드바에 현재 폴더 highlight 표시, `⌘R` reload 바인딩까지 마무리. M1.2/1.3/1.4 이월 polish 는 M1.6 폴리싱 마일스톤에서 처리.

**Architecture:**
- **디자인 토큰** — `CairnTheme` struct + `.glass` 인스턴스 + `@Environment(\.cairnTheme)` 주입. Phase 1 은 `.glass` 하나 고정, 스위처는 Phase 3.
- **Visual effect 레이어** — `VisualEffectBlur`(`NSVisualEffectView` NSViewRepresentable 래퍼). 루트 윈도우 `.hudWindow` material + 사이드바/프리뷰 패널은 `.sidebar` material 위에 `panelTint`/`sidebarTint` 를 `0.4 opacity` 로 overlay. 토크 색상은 SwiftUI `Color` primitive (hue/saturation/brightness).
- **컨텍스트 메뉴** — 기존 `FileListCoordinator.menu(for:)` 에 3 개 NSMenuItem 추가. **Copy Path** → `NSPasteboard.general.setString(...)`, `⌥⌘C` 바인딩. **Move to Trash** → `FileManager.default.trashItem(at:resultingItemURL:)`, `⌘⌫` 바인딩. **Open With** → `NSMenuItem.submenu` 로 `NSWorkspace.urlsForApplications(toOpen:)` 결과를 나열, 클릭 시 `NSWorkspace.shared.open([fileURL], withApplicationAt: ..., configuration: .init())`. 선택 여러 개일 땐 첫 항목 기준.
- **사이드바 highlight** — `SidebarItemRow` 에 `isSelected: Bool` 추가. `SidebarView` 가 각 row 의 URL 을 `app.currentFolder` 와 비교해 매칭 시 `theme.accentMuted` 배경. 일치 판단은 `URL.standardizedFileURL.path` 기준.
- **`⌘R` reload** — ContentView toolbar 에 `Button` + `.keyboardShortcut("r", modifiers: [.command])`. 액션은 `folder?.load(url)` 재호출 (security-scoped access 는 이미 유효).

**Tech Stack:** Swift 5.9 · SwiftUI (macOS 14+) · AppKit (`NSVisualEffectView`, `NSMenuItem`, `NSPasteboard`, `NSWorkspace`) · `FileManager.trashItem` · `@Observable` / `@Environment` / `EnvironmentKey`

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main branch, HEAD 시작은 `phase-1-m1.4` 태그)

**Predecessor:** M1.4 — `docs/superpowers/plans/2026-04-21-cairn-phase-1-m1.4-preview.md` (완료, tag `phase-1-m1.4`)
**Parent spec:** `docs/superpowers/specs/2026-04-21-cairn-phase-1-design.md` § 6 / § 8 / § 11 M1.5

**Deliverable verification (M1.5 완료 조건):**
- `cargo test --workspace` 녹색 (신규 Rust 없음; regression 만 확인)
- `xcodebuild build` 성공
- `xcodebuild test` 20/20 (신규 Swift 테스트 없음; M1.5 는 viewer/theme 계층이라 XCTest 최소 적합도 낮음 — visual regression 은 수동)
- 앱 실행 → 루트 윈도우 / 사이드바 / 프리뷰 패널 모두 반투명 블러 + 파란 cast (Glass Blue)
- 우클릭 파일 → "Open With" 서브메뉴 + "Copy Path" + "Move to Trash" 모두 동작
- `⌥⌘C` → pasteboard 에 경로 복사 (다른 앱에서 paste 가능)
- `⌘⌫` → 선택 파일들 trash 로 이동 (.Trash/ 에 들어감)
- 사이드바에서 현재 폴더 row 는 하이라이트 배경 (파란 muted)
- `⌘R` → 현재 폴더 리로드 (loading spinner 잠깐 후 다시 표시)
- `git tag phase-1-m1.5` 로 기준점

---

## 1. 기술 참조 (M1.5 특유 함정)

- **`NSVisualEffectView.Material.hudWindow`** — macOS Ventura+ 네이티브 블러. `deploymentTarget: 14.0` 이니 OK. 만약 `.hudWindow` 가 Sonoma 에서 기대와 다른 색감이면 `.sidebar` 로 폴백 (둘 다 light/dark 자동 반응).
- **`VisualEffectBlur` 를 SwiftUI `.background(...)` 으로 꽂을 때** — `NSViewRepresentable` 가 반환하는 view 는 SwiftUI `View` 와 달리 size-to-fit 을 알아서 안 함. `.frame(maxWidth: .infinity, maxHeight: .infinity)` 나 `.ignoresSafeArea()` 를 붙여야 전체 영역 채움.
- **`.listStyle(.sidebar)` 와 우리 material 의 충돌** — `List` 의 sidebar 스타일은 이미 AppKit 의 sidebar material 배경을 자동으로 적용한다. 우리가 `.background(VisualEffectBlur(material: .sidebar))` 를 넣으면 두 레이어가 겹친다. 두 방식:
  1. `.scrollContentBackground(.hidden)` 로 `List` 기본 배경 끄고 우리 blur 을 깔기
  2. 기본 sidebar material 그대로 두고 tint 오버레이만 추가
  플랜은 방식 1 채택 — 스펙 § 6 대로 "NSVisualEffectView 위에 tint 오버레이" 를 직접 구성.
- **Environment injection 시점** — `@Environment(\.cairnTheme)` 는 `EnvironmentKey` 가 `defaultValue: .glass` 를 제공하므로, 주입 없어도 preview/테스트에서 `.glass` 가 읽힌다. 실서비스엔 `CairnApp` 에서 `.environment(\.cairnTheme, .glass)` 로 명시 주입해서 의도가 명확하게.
- **`FileManager.trashItem(at:resultingItemURL:)`** — iOS 와 달리 macOS 에선 Trash 이동이 가능. Sandbox + user-selected scope 안에서 호출하면 OK. `resultingItemURL` 은 `UnsafeMutablePointer<NSURL?>?` 로 inout 받는 고전 API — 무시해도 동작.
- **`NSWorkspace.urlsForApplications(toOpen:)`** — macOS 12+ 에서 provided. 반환값은 기본 앱 포함 전체 후보. 기본 앱 따로 제일 위에 두려면 `NSWorkspace.urlForApplication(toOpen:)` 로 먼저 조회 후 dedupe.
- **Open With submenu** — `NSMenuItem` 의 `.submenu` property 에 `NSMenu` 할당. 각 서브 항목의 `representedObject` 에 `(fileURL, appURL)` 튜플 대신 **2 개의 separate property** 를 저장할 수 없으므로, 간단한 struct `OpenWithPayload { let fileURL: URL; let appURL: URL }` 를 만들어 reference-typed wrapper (`NSObject` subclass 또는 `class OpenWithPayload: NSObject { ... }`) 로 전달. 또는 closure 를 target-action 대신 `NSMenuItem.action` 으로 묶고 sender 로 구분. 플랜은 NSObject wrapper 선택 — 기존 `representedObject: entry as FileEntry` 패턴과 일관.
- **Keyboard shortcuts in NSMenuItem** — `⌥⌘C`: `keyEquivalent = "c"` + `keyEquivalentModifierMask = [.command, .option]`. `⌘⌫`: `keyEquivalent = String(UnicodeScalar(NSBackspaceCharacter)!)` + `keyEquivalentModifierMask = .command`. NSBackspaceCharacter = 0x08.
- **`NSPasteboard.general.clearContents()` 선호출** — `setString` 전에 pasteboard 비우기 필수 (Apple 권고). 안 하면 이전 앱의 타입과 뒤섞일 가능성.
- **사이드바 highlight 색상** — `accentMuted` (`#0A84FF` @ 22% alpha) 는 배경으로 사용 시 light/dark mode 모두 자연스러움. row 의 ` .background(theme.accentMuted)` + `.clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))`.
- **`⌘R` ↔ QLPreviewPanel conflict** — QLPreviewPanel 이 떠 있는 상태에서 `⌘R` 은 panel 자체가 key-responder 라 ContentView toolbar 의 keyboardShortcut 이 동작 안 함. 의도된 동작. (유저 수동 E2E 에서 주의.)
- **이월 polish 범위 주의** — 이 플랜 **안 다룸**. M1.2/1.3/1.4 의 남은 polish 항목은 모두 M1.6 플랜으로. 본 플랜 Task 범위를 벗어나는 리팩터는 하지 않는다.

---

## 2. File Structure

**신규:**
- Create: `apps/Sources/Theme/CairnTheme.swift` (struct + `.glass` instance + EnvironmentKey + EnvironmentValues extension)
- Create: `apps/Sources/Views/VisualEffectBlur.swift` (NSViewRepresentable wrapper for `NSVisualEffectView`)

**수정:**
- Modify: `apps/Sources/CairnApp.swift` (주입 + 루트 material)
- Modify: `apps/Sources/Views/Sidebar/SidebarView.swift` (Glass Blue 적용 + highlight)
- Modify: `apps/Sources/Views/Sidebar/SidebarItemRow.swift` (`isSelected` 파라미터 추가)
- Modify: `apps/Sources/Views/Preview/PreviewPaneView.swift` (Glass Blue 적용 + 테마 폰트)
- Modify: `apps/Sources/Views/FileList/FileListCoordinator.swift` (컨텍스트 메뉴 3 항목 추가)
- Modify: `apps/Sources/ContentView.swift` (`⌘R` toolbar button + reload helper)

---

## Task 1: `CairnTheme` — 디자인 토큰 + EnvironmentKey

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Theme/CairnTheme.swift`

스펙 § 6 verbatim + Swift `EnvironmentKey` / `EnvironmentValues` extension 으로 주입 가능하게.

- [ ] **Step 1: 디렉터리 생성 + 파일 작성**

파일 `apps/Sources/Theme/CairnTheme.swift` 를 다음으로 생성 (디렉터리는 없으므로 자동 생성됨):

```swift
import SwiftUI
import AppKit

/// Design tokens for Cairn's visual theme.
///
/// Phase 1 ships a single `.glass` instance (Glass Blue). The theme switcher
/// is Phase 3. Consumers read via `@Environment(\.cairnTheme)`; the default
/// value is `.glass`, so tests and previews work without explicit injection.
struct CairnTheme: Equatable {
    let id: String
    let displayName: String

    // Window / panels
    let windowMaterial: NSVisualEffectView.Material
    let sidebarTint: Color
    let panelTint: Color

    // Text
    let text: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent
    let accent: Color
    let accentMuted: Color
    let selectionFg: Color

    // Geometry
    let cornerRadius: CGFloat
    let rowHeight: CGFloat
    let sidebarRowHeight: CGFloat
    let panelPadding: EdgeInsets

    // Typography
    let bodyFont: Font
    let monoFont: Font
    let headerFont: Font

    // Layout (Phase 1 엔 threePane 하나)
    let layout: LayoutVariant
}

enum LayoutVariant { case threePane, paletteFirst }

extension CairnTheme {
    static let glass = CairnTheme(
        id: "glass",
        displayName: "Glass (Blue)",
        windowMaterial: .hudWindow,
        sidebarTint: Color(hue: 0.62, saturation: 0.08, brightness: 0.14),
        panelTint:   Color(hue: 0.62, saturation: 0.06, brightness: 0.12),
        text:          Color(white: 0.93),
        textSecondary: Color(white: 0.60),
        textTertiary:  Color(white: 0.42),
        accent:        Color(red: 0.04, green: 0.52, blue: 1.00),   // #0A84FF
        accentMuted:   Color(red: 0.04, green: 0.52, blue: 1.00, opacity: 0.22),
        selectionFg:   .white,
        cornerRadius: 6,
        rowHeight: 24,
        sidebarRowHeight: 22,
        panelPadding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
        bodyFont:   .system(size: 12),
        monoFont:   .system(size: 11, design: .monospaced),
        headerFont: .system(size: 10, weight: .semibold),
        layout: .threePane
    )
}

// MARK: - Environment

private struct CairnThemeKey: EnvironmentKey {
    static let defaultValue: CairnTheme = .glass
}

extension EnvironmentValues {
    var cairnTheme: CairnTheme {
        get { self[CairnThemeKey.self] }
        set { self[CairnThemeKey.self] = newValue }
    }
}
```

- [ ] **Step 2: xcodegen + 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 아직 아무도 `cairnTheme` 을 읽지 않으므로 앱 동작 변화 없음.

- [ ] **Step 3: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20 여전히 통과.

- [ ] **Step 4: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Theme/CairnTheme.swift
git commit -m "feat(theme): add CairnTheme struct + .glass tokens + EnvironmentKey"
```

---

## Task 2: `VisualEffectBlur` — NSVisualEffectView SwiftUI 래퍼

**Files:**
- Create: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/VisualEffectBlur.swift`

SwiftUI 에서 `NSVisualEffectView` 를 `.background(...)` 으로 꽂을 수 있게 하는 래퍼. Task 3-5 에서 사용.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI
import AppKit

/// SwiftUI wrapper over `NSVisualEffectView`. Plant as a `.background(...)`
/// or inside a `ZStack` to get macOS native blur (translucency + vibrancy).
///
/// Usage:
///   VStack { … }
///     .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea())
///
/// The `.active` state forces always-on blur regardless of window focus;
/// switch to `.followsWindowActiveState` if you want the system-default
/// desaturated-when-unfocused look.
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/VisualEffectBlur.swift
git commit -m "feat(theme): add VisualEffectBlur NSViewRepresentable wrapper"
```

---

## Task 3: `CairnApp` — 테마 주입 + 루트 윈도우 material

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/CairnApp.swift`

현재 `CairnApp.body` 는:

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .environment(app)
            .frame(minWidth: 800, minHeight: 500)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
}
```

`.environment(\.cairnTheme, .glass)` 주입 + 루트 배경을 `VisualEffectBlur(material: .hudWindow)` 로 교체.

- [ ] **Step 1: `CairnApp.swift` 수정**

`WindowGroup { ... }` 블록 전체를 다음으로 교체:

```swift
        WindowGroup {
            ContentView()
                .environment(app)
                .environment(\.cairnTheme, .glass)
                .frame(minWidth: 800, minHeight: 500)
                .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea())
        }
```

- [ ] **Step 2: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 수동 확인 (선택, 최종 Task 10 에서 체크)**

앱 실행 시 윈도우 chrome (타이틀 바 영역) 에 블러가 적용되어 반투명 배경 위로 바탕화면 흐릿하게 비침. 내부 content 영역은 아직 `List`/`NavigationSplitView` 기본 색상 — Task 4/5 에서 Glass Blue tint 로 마감.

- [ ] **Step 4: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/CairnApp.swift
git commit -m "feat(app): inject .glass theme + apply .hudWindow root material"
```

---

## Task 4: `SidebarView` — Glass Blue 적용 (material + tint + fonts)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Sidebar/SidebarView.swift`

현재 `SidebarView.body` 는 `List { ... }.listStyle(.sidebar).frame(minWidth: 200)` 로 끝난다. 다음 변경:
1. `@Environment(\.cairnTheme)` 주입
2. `List` 기본 배경 끄기 (`.scrollContentBackground(.hidden)`)
3. `List` 뒤에 `VisualEffectBlur(material: .sidebar)` + `panelTint` 오버레이 0.4 opacity
4. `Section` header 폰트를 `theme.headerFont` 로

하이라이트 (isSelected 로직) 는 Task 7 에서 따로. 이 Task 는 material/tint/font 만.

- [ ] **Step 1: import + environment 추가**

파일 상단 (`import AppKit` 바로 다음 줄) 은 이미 `import AppKit` 이 있으므로 유지. `@Bindable var app: AppModel` 바로 아래에 새 line 추가:

```swift
    @Bindable var app: AppModel
    @Environment(\.cairnTheme) private var theme
```

- [ ] **Step 2: `body` 최하단 `.listStyle(.sidebar).frame(minWidth: 200)` 교체**

기존:
```swift
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
```

다음으로 교체 (중괄호는 `body` 내 모든 `Section` 을 감싸는 `List` 의 닫는 부분임):

```swift
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                VisualEffectBlur(material: .sidebar)
                theme.sidebarTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 200)
    }
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. 사이드바 영역이 이제 파란 cast 가 있는 반투명 블러로 보인다.

- [ ] **Step 4: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Sidebar/SidebarView.swift
git commit -m "feat(sidebar): apply Glass Blue theme (material + tint)"
```

---

## Task 5: `PreviewPaneView` — Glass Blue 적용 (material + tint + theme fonts)

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Preview/PreviewPaneView.swift`

현재 `PreviewPaneView.body` 는 `VStack(spacing: 0) { ... }.frame(maxWidth: .infinity, maxHeight: .infinity)` 로 끝난다. `VStack` 뒤에 Glass Blue 배경 추가. 헤더 폰트도 `theme.headerFont` 로 교체.

- [ ] **Step 1: environment 추가**

`@Bindable var preview: PreviewModel` 바로 아래에:

```swift
    @Bindable var preview: PreviewModel
    @Environment(\.cairnTheme) private var theme
```

- [ ] **Step 2: `body` 의 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 뒤에 배경 추가**

기존:
```swift
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
```

다음으로 교체:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if let url = preview.focus, !isIdle {
                header(for: url)
                Divider()
            }
            renderer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBlur(material: .contentBackground)
                theme.panelTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
    }
```

- [ ] **Step 3: `header(for:)` 내부 첫 두 `Text` 를 theme 폰트로**

기존 (function body):
```swift
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
```

다음으로 교체 (filename 은 `theme.bodyFont.weight(.medium)` 로, 나머지 두 `.font(.system(size: 10))` 는 `theme.headerFont` 로):

```swift
    private func header(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(theme.bodyFont.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().path)
                .font(theme.headerFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            if let size = fileSize(for: url) {
                Text(size)
                    .font(theme.headerFont)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

- [ ] **Step 4: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Preview/PreviewPaneView.swift
git commit -m "feat(preview): apply Glass Blue theme (material + tint + fonts)"
```

---

## Task 6: 컨텍스트 메뉴 확장 — Copy Path / Move to Trash / Open With

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/FileList/FileListCoordinator.swift`

기존 `menu(for:)` 는 "Add to Pinned"(디렉터리) + separator + "Reveal in Finder" 를 만든다. 다음 3 개 항목 추가:
1. **Copy Path** (`⌥⌘C`) — `entry.path` 를 pasteboard 에.
2. **Move to Trash** (`⌘⌫`) — `FileManager.trashItem(at:)`.
3. **Open With** — `NSMenuItem.submenu` 로 `NSWorkspace.urlsForApplications(toOpen:)` 결과 나열.

메뉴 순서: Add to Pinned (폴더만) → separator → Reveal → Copy Path → Open With → separator → Move to Trash.

- [ ] **Step 1: `FileListCoordinator.swift` — 파일 상단에 `OpenWithPayload` 헬퍼 클래스 추가**

기존 `import AppKit` / `import SwiftUI` / `import QuickLookUI` 라인 바로 아래 (클래스 선언 위) 에 다음 헬퍼 추가:

```swift
/// `representedObject` can only hold a single value, so wrap `(fileURL, appURL)`
/// as an NSObject so the target-action path can recover both when the user
/// clicks an app inside the "Open With" submenu.
final class OpenWithPayload: NSObject {
    let fileURL: URL
    let appURL: URL
    init(fileURL: URL, appURL: URL) {
        self.fileURL = fileURL
        self.appURL = appURL
    }
}
```

- [ ] **Step 2: `menu(for:)` 확장**

현재 `menu(for:)` 함수 전체 (기존 위치 유지):

```swift
    func menu(for event: NSEvent) -> NSMenu? {
        guard let table = self.table else { return nil }
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]

        let menu = NSMenu()

        if entry.kind == .Directory {
            let item = NSMenuItem(
                title: isPinnedCheck(entry) ? "Unpin" : "Add to Pinned",
                action: #selector(menuAddToPinned(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(menuRevealInFinder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry
        menu.addItem(reveal)

        return menu
    }
```

다음으로 교체:

```swift
    func menu(for event: NSEvent) -> NSMenu? {
        guard let table = self.table else { return nil }
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        guard row >= 0, row < lastSnapshot.count else { return nil }
        let entry = lastSnapshot[row]

        let menu = NSMenu()

        if entry.kind == .Directory {
            let item = NSMenuItem(
                title: isPinnedCheck(entry) ? "Unpin" : "Add to Pinned",
                action: #selector(menuAddToPinned(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = entry
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(menuRevealInFinder(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = entry
        menu.addItem(reveal)

        // Copy Path (⌥⌘C) — stays just below Reveal so the two OS-level ops sit together.
        let copyPath = NSMenuItem(title: "Copy Path",
                                  action: #selector(menuCopyPath(_:)),
                                  keyEquivalent: "c")
        copyPath.keyEquivalentModifierMask = [.command, .option]
        copyPath.target = self
        copyPath.representedObject = entry
        menu.addItem(copyPath)

        // Open With submenu — non-directories only. Directories go straight to Finder.
        if entry.kind != .Directory {
            if let openWith = buildOpenWithSubmenu(for: entry) {
                let openItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                openItem.submenu = openWith
                menu.addItem(openItem)
            }
        }

        menu.addItem(.separator())

        // Move to Trash (⌘⌫) — destructive, separated by divider.
        let trash = NSMenuItem(title: "Move to Trash",
                               action: #selector(menuMoveToTrash(_:)),
                               keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
        trash.keyEquivalentModifierMask = .command
        trash.target = self
        trash.representedObject = entry
        menu.addItem(trash)

        return menu
    }

    private func buildOpenWithSubmenu(for entry: FileEntry) -> NSMenu? {
        let fileURL = URL(fileURLWithPath: entry.path.toString())
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        guard !appURLs.isEmpty else { return nil }

        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)

        // Put default app first (bold via attributedTitle), then the rest.
        var ordered: [URL] = []
        if let def = defaultApp {
            ordered.append(def)
            ordered.append(contentsOf: appURLs.filter { $0 != def })
        } else {
            ordered = appURLs
        }

        for appURL in ordered {
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            let title = (appURL == defaultApp) ? "\(name) (default)" : name
            let item = NSMenuItem(title: title,
                                  action: #selector(menuOpenWith(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = OpenWithPayload(fileURL: fileURL, appURL: appURL)
            submenu.addItem(item)
        }
        return submenu
    }
```

- [ ] **Step 3: 새 action 메서드 3 개 추가**

기존 `@objc private func menuRevealInFinder(_ sender: NSMenuItem) { ... }` 메서드 아래에 다음 3 개를 추가:

```swift
    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        let path = entry.path.toString()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
    }

    @objc private func menuMoveToTrash(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? FileEntry else { return }
        let url = URL(fileURLWithPath: entry.path.toString())
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSLog("cairn: Move to Trash failed — \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    @objc private func menuOpenWith(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? OpenWithPayload else { return }
        NSWorkspace.shared.open([payload.fileURL],
                                withApplicationAt: payload.appURL,
                                configuration: .init()) { _, error in
            if let error { NSLog("cairn: Open With failed — \(error.localizedDescription)") }
        }
    }
```

- [ ] **Step 4: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 6: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/FileList/FileListCoordinator.swift
git commit -m "feat(file-list): context menu — Copy Path / Move to Trash / Open With"
```

---

## Task 7: Sidebar current-folder highlight

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Sidebar/SidebarItemRow.swift`
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/Views/Sidebar/SidebarView.swift`

`SidebarItemRow` 에 `isSelected: Bool` 추가. `SidebarView` 는 각 row 생성 시 URL 을 `app.currentFolder` 와 비교해 계산.

- [ ] **Step 1: `SidebarItemRow.swift` — `isSelected` 추가**

기존 파일 전체 교체:

```swift
import SwiftUI

/// Single sidebar row — icon + label. Used for every section so all items line
/// up visually and we have one place to tune padding/size. When `isSelected`
/// is true, the row gets a theme-accented pill background so the user always
/// knows which source the current folder belongs to.
struct SidebarItemRow: View {
    let icon: String      // SF Symbol name
    let label: String
    let tint: Color?      // if nil, label color is used
    var isSelected: Bool = false

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        Label {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 16)
        }
        .font(theme.bodyFont)
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.accentMuted)
            }
        }
    }
}
```

- [ ] **Step 2: `SidebarView.swift` — path matcher + isSelected wire-up**

파일 전체 교체:

```swift
import SwiftUI
import AppKit

/// Finder-like 4-section sidebar: Pinned / Recent / iCloud Drive / Locations.
/// Clicking an item navigates via AppModel. Right-click gives "Add to Pinned",
/// "Unpin", or "Reveal in Finder" depending on the item's section. The row that
/// matches the current folder gets a theme-accented highlight.
struct SidebarView: View {
    @Bindable var app: AppModel
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        List {
            if !app.bookmarks.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(app.bookmarks.pinned) { entry in
                        pinnedRow(entry)
                    }
                }
            }

            if !app.bookmarks.recent.isEmpty {
                Section("Recent") {
                    ForEach(app.bookmarks.recent) { entry in
                        recentRow(entry)
                    }
                }
            }

            if let iCloud = app.sidebar.iCloudURL {
                Section("iCloud") {
                    row(url: iCloud,
                        icon: "icloud",
                        label: "iCloud Drive",
                        tint: .blue,
                        canPin: true)
                }
            }

            Section("Locations") {
                ForEach(app.sidebar.locations, id: \.self) { loc in
                    row(url: loc,
                        icon: loc.path == "/" ? "desktopcomputer" : "externaldrive",
                        label: locationLabel(loc),
                        tint: nil,
                        canPin: true)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                VisualEffectBlur(material: .sidebar)
                theme.sidebarTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 200)
    }

    // MARK: - Rows

    private func pinnedRow(_ entry: BookmarkEntry) -> some View {
        let url = URL(fileURLWithPath: entry.lastKnownPath)
        return SidebarItemRow(
            icon: "pin.fill",
            label: entry.label ?? url.lastPathComponent,
            tint: .orange,
            isSelected: isCurrent(url)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Unpin") { app.bookmarks.unpin(entry) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func recentRow(_ entry: BookmarkEntry) -> some View {
        let url = URL(fileURLWithPath: entry.lastKnownPath)
        return SidebarItemRow(
            icon: "clock",
            label: url.lastPathComponent,
            tint: nil,
            isSelected: isCurrent(url)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Add to Pinned") { try? app.bookmarks.togglePin(url: URL(fileURLWithPath: entry.lastKnownPath)) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func row(url: URL, icon: String, label: String, tint: Color?, canPin: Bool) -> some View {
        SidebarItemRow(icon: icon, label: label, tint: tint, isSelected: isCurrent(url))
            .contentShape(Rectangle())
            .onTapGesture { app.navigateUnscoped(to: url) }
            .contextMenu {
                if canPin {
                    if app.bookmarks.isPinned(url: url) {
                        Button("Unpin") { try? app.bookmarks.togglePin(url: url) }
                    } else {
                        Button("Add to Pinned") { try? app.bookmarks.togglePin(url: url) }
                    }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(url.path,
                                                  inFileViewerRootedAtPath: "")
                }
            }
    }

    private func locationLabel(_ url: URL) -> String {
        if url.path == "/" {
            return Host.current().localizedName ?? "Computer"
        }
        return url.lastPathComponent
    }

    /// Compare against `app.currentFolder` using the standardized path form so
    /// `/tmp/foo` and `/private/tmp/foo` and `/tmp/./foo` all match one another.
    private func isCurrent(_ url: URL) -> Bool {
        guard let current = app.currentFolder else { return false }
        return url.standardizedFileURL.path == current.standardizedFileURL.path
    }
}
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/Views/Sidebar/SidebarItemRow.swift apps/Sources/Views/Sidebar/SidebarView.swift
git commit -m "feat(sidebar): highlight current-folder row via theme.accentMuted"
```

---

## Task 8: `⌘R` reload

**Files:**
- Modify: `/Users/cyj/workspace/personal/cairn/apps/Sources/ContentView.swift`

toolbar 에 reload 버튼 추가 + `Button` 에 `.keyboardShortcut("r", modifiers: [.command])`. 액션은 기존 `folder?.load(url)` 재호출.

- [ ] **Step 1: toolbar 항목 추가**

현재 `.toolbar { ... }` 블록 내 마지막 항목 (hidden-files toggle) 바로 아래에 새 `ToolbarItem` 추가. 기존 마지막 toolbar item:

```swift
            ToolbarItem(placement: .automatic) {
                Button(action: { toggleShowHidden() }) {
                    Image(systemName: app.showHidden ? "eye" : "eye.slash")
                }
                .help(app.showHidden ? "Hide hidden files" : "Show hidden files")
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
```

바로 다음에 추가:

```swift
            ToolbarItem(placement: .automatic) {
                Button(action: { reloadCurrentFolder() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(app.currentFolder == nil)
            }
```

- [ ] **Step 2: `reloadCurrentFolder` 헬퍼 추가**

기존 `toggleShowHidden()` 메서드 바로 아래에 추가:

```swift
    private func reloadCurrentFolder() {
        guard let url = app.currentFolder else { return }
        Task { await folder?.load(url) }
    }
```

- [ ] **Step 3: 빌드**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodegen generate
xcodebuild -scheme Cairn -configuration Debug build CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 테스트 regression**

```bash
cd /Users/cyj/workspace/personal/cairn/apps
xcodebuild test -scheme CairnTests -destination "platform=macOS" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -5
```

Expected: 20/20.

- [ ] **Step 5: 커밋**

```bash
cd /Users/cyj/workspace/personal/cairn
git add apps/Sources/ContentView.swift
git commit -m "feat(app): add ⌘R reload toolbar button"
```

---

## Task 9: 수동 E2E (사용자 수행)

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

**Glass Blue 시각 확인:**
- [ ] 윈도우 전체 배경이 반투명 블러 (바탕화면 흐릿하게 비침)
- [ ] 사이드바 영역이 파란 cast + 블러 (`sidebarTint` 적용)
- [ ] 프리뷰 패널이 파란 cast + 블러 (`panelTint` 적용)
- [ ] Sidebar Section 헤더 (Pinned/Recent/iCloud/Locations) 이 일관된 폰트
- [ ] 프리뷰 헤더의 파일명/경로/크기 텍스트가 `theme.bodyFont` / `theme.headerFont` 반영

**컨텍스트 메뉴:**
- [ ] 파일 우클릭 → 메뉴에 "Reveal in Finder" / "Copy Path" / "Open With ▸" / separator / "Move to Trash" 표시
- [ ] 폴더 우클릭 → 기존 "Add to Pinned/Unpin" + separator + "Reveal in Finder" + "Copy Path" + "Move to Trash" (Open With 은 폴더에 없음)
- [ ] **Copy Path (`⌥⌘C`)** → 경로가 클립보드에 복사됨, 다른 앱에서 `⌘V` paste 로 확인
- [ ] **Open With** → 서브메뉴에 파일 타입에 맞는 앱들이 열리고, 기본 앱 옆에 "(default)" 표시. 앱 하나 클릭 → 해당 앱으로 파일 열림
- [ ] **Move to Trash (`⌘⌫`)** → 파일이 `~/.Trash/` 로 이동, 리스트에서 사라짐
- [ ] Move to Trash 실패 (예: 시스템 보호 폴더) → 비프 음 + NSLog 에 에러 (Console.app)

**사이드바 highlight:**
- [ ] 사이드바에서 특정 folder 클릭 → 해당 row 에 파란 accentMuted 배경 highlight
- [ ] 다른 folder 로 이동 → 이전 highlight 는 사라지고 새 row 가 highlight
- [ ] Pinned / Recent / iCloud / Locations 모두 동일하게 동작

**`⌘R` reload:**
- [ ] `⌘R` 누름 → 잠깐 loading 스피너 후 리스트 재렌더 (외부에서 파일 추가/삭제했다면 즉시 반영됨)
- [ ] toolbar 의 `arrow.clockwise` 버튼 클릭해도 동일

**Regression (M1.2 / M1.3 / M1.4):**
- [ ] 파일 프리뷰 (텍스트/이미지/binary/directory/idle) 모두 정상
- [ ] `Space` → QLPreviewPanel 정상
- [ ] `⌘⇧.` 숨김 토글 정상
- [ ] `⌘D` pin 토글 정상
- [ ] 브레드크럼, ↑↓ 내비, ⏎ / 더블클릭, 컬럼 정렬 모두 정상

문제 발견 시 어떤 항목이 안 되는지 메모, STOP.

- [ ] **Step 3: 커밋 불필요**

---

## Task 10: 워크스페이스 sanity + tag

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
- cargo test: 기존 workspace 테스트 전부 통과 (M1.5 는 Rust 신규 없음)
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

(M1.5 는 Rust 코드 변경 없으므로 fmt 는 clean 이어야 정상. 만약 dirty 면 이전 마일스톤 미정리본 — 확인 후 커밋.)

- [ ] **Step 3: tag**

```bash
cd /Users/cyj/workspace/personal/cairn
git tag phase-1-m1.5
git log --oneline phase-1-m1.4..phase-1-m1.5
```

Expected: M1.5 커밋 약 8 개 (Task 1-8 각 1 커밋).

- [ ] **Step 4: tag 확인**

```bash
git tag -l | grep phase
```

Expected: `phase-1-m1.1`, `phase-1-m1.2`, `phase-1-m1.3`, `phase-1-m1.4`, `phase-1-m1.5`.

---

## 🎯 M1.5 Definition of Done

- [ ] `CairnTheme` struct + `.glass` 인스턴스 + `@Environment(\.cairnTheme)` 주입
- [ ] `VisualEffectBlur` NSViewRepresentable 래퍼
- [ ] 루트 윈도우 `.hudWindow` material 적용
- [ ] 사이드바 Glass Blue (material + `sidebarTint` 오버레이)
- [ ] 프리뷰 패널 Glass Blue (material + `panelTint` 오버레이 + theme 폰트)
- [ ] 컨텍스트 메뉴: Copy Path (`⌥⌘C`) / Move to Trash (`⌘⌫`) / Open With submenu 추가
- [ ] 사이드바 현재 폴더 row highlight
- [ ] `⌘R` reload (toolbar 버튼 + 키보드 shortcut)
- [ ] `xcodebuild test` 20/20
- [ ] `cargo test --workspace` + `cargo clippy -- -D warnings` 녹색
- [ ] `git tag phase-1-m1.5` 존재

---

## 이월된 follow-up (M1.6 에서 처리)

이 플랜은 **M1.5 본편만** 다룬다. 다음 항목들은 모두 M1.6 폴리싱 마일스톤 범위:

**M1.2 잔여:**
- `sortDescriptorsDidChange` 재진입 주석
- `@Bindable var folder` → `let folder` (read-only)
- `modified_unix==0` sentinel 주석
- `activateSelected` multi-row 동작 정립

**M1.3 잔여:**
- `representedObject` → `MenuPayload` 리팩터 (OpenWithPayload 패턴과 통합)
- `SidebarModelTests` 반응성 테스트 누락
- `isPinned(url:)` plan 스펙 drift 정리

**M1.4 잔여 (리뷰에서 발견):**
- `PreviewModel` `@MainActor` 적용 + `compute` 의 FileManager 호출을 `Task.detached` 로 분리 (Swift 6 strict-concurrency 대비)
- `ImagePreview` path 변경 시 `image = nil` reset (stale 이미지 깜빡임)
- `quickLookURLs` → `beginPreviewPanelControl` 에서 snapshot 캡처
- `cairn-ffi/Cargo.toml` 의 unused `cairn-preview` dep 제거
- `cairn-core` `WalkerError` re-export 일관성
- 모듈 docstring 업데이트 (`cairn-core`, `CairnEngine`)
- `preview_text(max_bytes=0)` 가드
- `String(describing: error)` → user-facing error mapping

**M1.5 에서 알려진 polish (M1.6 에서 같이):**
- Glass Blue 톤의 macOS 13 호환성 확인 (`deploymentTarget` 이 14 이면 무시)
- `VisualEffectBlur` 의 `.followsWindowActiveState` 옵션 (포커스 잃으면 데사처레이트) — 현재는 `.active` 고정
- 사이드바 highlight 가 dark mode 에서 `accentMuted` 채도 재검토 (육안 확인)
- `Open With` 서브메뉴 캐시 (현재는 메뉴 열 때마다 `urlsForApplications(toOpen:)` 호출 — 파일 타입 단위 캐시 가능)
- "Move to Trash" 실패 시 사용자 다이얼로그 (현재는 NSSound.beep + NSLog)
- `Copy Path` 의 POSIX/HFS 모드 선택 (현재는 POSIX 만)

---

## 다음 마일스톤 (M1.6)

M1.6 는 **폴리싱 + 버그 + v0.1.0-alpha** (spec § 11):
- E2E 체크리스트 완주 (spec § 9)
- 위 이월 polish 전부 흡수
- README / USAGE 업데이트
- `create-dmg` 실험 (distribution 엔 미등록 OK)
- `git tag v0.1.0-alpha`

M1.6 플랜은 M1.5 완료 직후 작성 (실행 러닝 반영).
