# Cairn App Icon — Design Spec

**Status:** approved 2026-04-22
**Scope:** macOS `.icns` app icon for Cairn v0.1.x+

## Concept

**Geometric cairn — four stacked rounded-rectangle tiles on a deep-blue field, with a dawn-light color gradient running bottom-to-top (slate → cool white → warm cream → gold).**

- **Metaphor.** Tiles stacked like a hiking cairn — the name is literal. Tiles also read as files/panels, linking the icon to the app's three-pane browser. The dawn gradient frames the cairn as a *lit landmark*, not a pile.
- **Why this direction** (vs. literal stones / "C" monogram / waypoint):
  - Matches the app's Glass Blue theme language (rounded rect + blue + subtle glass).
  - Survives small sizes (16/32 px Finder rows) because silhouette is high-contrast geometric primitives, not organic pebbles.
  - The dawn coloring gives the icon a point of interest at the apex — avoids looking like yet another "stacked cards" utility.

## Visual spec

### Canvas

- Master render size: **1024 × 1024**
- Shape: squircle, `rx = ry = 115/512 * size` (≈22.5% of edge).
- No outer transparent padding inside the squircle; macOS compositor applies its own margin.

### Background

Vertical gradient top → bottom:
| stop | color    |
|-----:|:---------|
| 0%   | `#3E95FF` |
| 55%  | `#0F378A` |
| 100% | `#061A50` |

Top highlight overlay: radial gradient from `rgba(255,255,255,0.30)` (top-center) to transparent, clipped to the upper 55% of the canvas.

**Dawn glow** behind the top tile: radial ellipse centered at `(50%, 27%)`, radius ≈35% of canvas, color `rgba(255,208,122,0.18)` → transparent.

### Tile palette (bottom → top, "stone getting caught by sunrise")

| # | role   | top stop    | bottom stop |
|--:|:-------|:------------|:------------|
| 1 | bottom | `#C4D1E6`   | `#5A6E8E`   |
| 2 | middle | `#E8EEFA`   | `#9DB3D6`   |
| 3 | upper  | `#FDF2D9`   | `#D8C39A`   |
| 4 | top    | `#FFEEC2`   | `#E8B76A`   |

Each tile also has a 4 px white specular strip along the top edge (opacity ramps 0.45 / 0.55 / 0.60 / 0.70 bottom→top).

### Geometry (in 512-unit viewBox; scale linearly to 1024)

| # | role   | x   | y   | w   | h  | rx | rotation |
|--:|:-------|----:|----:|----:|---:|---:|---------:|
| 1 | bottom |  88 | 354 | 336 | 62 | 22 |   0°     |
| 2 | middle | 124 | 272 | 264 | 62 | 20 |  −2.2°   |
| 3 | upper  | 162 | 188 | 188 | 60 | 18 |  +1.8°   |
| 4 | top    | 198 | 104 | 116 | 56 | 16 |  −1.5°   |

Rotations pivot around each rect's own center.

### Shadows

- **Per-tile drop shadow:** duplicate shape offset +4 y, black @ opacity 0.25–0.30, `feGaussianBlur stdDeviation=3`, rendered *behind* the tile fill.
- **Ground shadow:** ellipse `cx=256 cy=425 rx=168 ry=10`, black @ opacity 0.45, `stdDeviation=3`.

## Deliverables

1. **Master SVG source** — `apps/Resources/AppIcon.svg` (hand-edited, commit as source of truth).
2. **Rendered PNGs** — the standard macOS app-icon set (10 files): 16×16 @1x/@2x, 32×32 @1x/@2x, 128×128 @1x/@2x, 256×256 @1x/@2x, 512×512 @1x/@2x. Pixel sizes span 16 → 1024.
3. **Asset catalog** — `apps/Resources/Assets.xcassets/AppIcon.appiconset/` populated with the PNGs and `Contents.json`.
4. **Derived `.icns`** — optional, for standalone bundling; Xcode generates the runtime icon from the asset catalog.
5. **Info.plist** — add `CFBundleIconName = AppIcon`.

## Rendering pipeline

Prefer **`rsvg-convert`** (via `librsvg`) over `qlmanage`/`sips` because it produces consistent alpha and gradient fidelity. Fallback to ImageMagick if unavailable. Renderer selection + invocation lives in a new script:

- `scripts/render-icon.sh` — inputs SVG, outputs the 10 PNGs (`icon_16x16.png`, `icon_16x16@2x.png`, ..., `icon_512x512@2x.png`) into the `AppIcon.appiconset`.

The script should be idempotent and re-runnable from a clean checkout.

## Xcode integration

- `apps/project.yml` already lists `Resources` as a resource build phase — adding `Assets.xcassets` there is sufficient.
- Add `CFBundleIconName: AppIcon` to `apps/Sources/Info.plist`.
- Verify with `xcodebuild -scheme Cairn build` → the built `Cairn.app/Contents/Resources/AppIcon.icns` must exist.

## Non-goals (this spec)

- Dark-mode / light-mode alternate icons (single icon works in both contexts by design).
- Themed icon (iOS 18 style tintable variants).
- Dock badging, menu-bar glyph, or document icons — separate spec when needed.
- Animated / motion variants.

## Acceptance criteria

- [ ] `AppIcon.svg` exists and renders byte-identically on re-run of `render-icon.sh`.
- [ ] `AppIcon.appiconset` has all 10 required sizes, no gaps.
- [ ] Built `Cairn.app` shows the icon in Finder, Dock, and Cmd-Tab.
- [ ] At 16 px, all four tiles are still distinguishable as separate horizontal bands.
- [ ] Visual regression: 1024 PNG diff vs. committed reference is zero under `rsvg-convert` (dev machine).

## Open questions

None — all decisions locked during brainstorm (see `.superpowers/brainstorm/84194-1776854802/content/final-b4.html`).
