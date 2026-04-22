# Cairn App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production-grade `AppIcon.appiconset` for Cairn so the app shows a real icon in Finder/Dock/Cmd-Tab — derived deterministically from a single committed SVG source.

**Architecture:** One hand-edited `AppIcon.svg` (1024-unit canvas) is the source of truth. A `scripts/render-icon.sh` pipeline calls `rsvg-convert` to rasterize the 10 PNGs required by the macOS asset catalog. `project.yml` gains `CFBundleIconName = AppIcon` so `xcodegen` wires it into `Info.plist`. Rendered PNGs are committed so a cloner without librsvg still builds the app.

**Tech Stack:** SVG 1.1 (no external assets, no text), `librsvg` (`rsvg-convert`), `xcodegen`, Xcode asset catalog, Bash.

**Reference spec:** `docs/superpowers/specs/2026-04-22-cairn-app-icon-design.md`

---

## Prerequisites

- `librsvg` installed: `brew install librsvg` (provides `rsvg-convert`)
- `xcodegen` already in the project toolchain (per README)

## File structure

| Path | Kind | Purpose |
|------|------|---------|
| `apps/Resources/AppIcon.svg` | create | Master SVG source (1024×1024 viewBox) |
| `scripts/render-icon.sh` | create | Deterministic PNG renderer (SVG → 10 PNGs) |
| `apps/Resources/Assets.xcassets/Contents.json` | create | Root catalog descriptor |
| `apps/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | create | AppIcon descriptor (maps 10 PNGs to slots) |
| `apps/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png` | create | 10 rendered PNGs (committed) |
| `apps/project.yml` | modify | Add `CFBundleIconName: AppIcon` under `targets.Cairn.info.properties` |

---

## Task 1: Author the master SVG

**Files:**
- Create: `apps/Resources/AppIcon.svg`

- [ ] **Step 1: Write the SVG source**

Create `apps/Resources/AppIcon.svg` with this exact content (coordinates are in a 1024-unit viewBox; rotations pivot on each tile's own center):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3E95FF"/>
      <stop offset="0.55" stop-color="#0F378A"/>
      <stop offset="1" stop-color="#061A50"/>
    </linearGradient>
    <radialGradient id="topHi" cx="0.5" cy="0" r="0.85">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.30"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="dawnGlow" cx="0.5" cy="0.27" r="0.35">
      <stop offset="0" stop-color="#FFD07A" stop-opacity="0.18"/>
      <stop offset="1" stop-color="#FFD07A" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="tBtm" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#C4D1E6"/>
      <stop offset="1" stop-color="#5A6E8E"/>
    </linearGradient>
    <linearGradient id="tMid" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E8EEFA"/>
      <stop offset="1" stop-color="#9DB3D6"/>
    </linearGradient>
    <linearGradient id="tUpper" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FDF2D9"/>
      <stop offset="1" stop-color="#D8C39A"/>
    </linearGradient>
    <linearGradient id="tTop" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFEEC2"/>
      <stop offset="1" stop-color="#E8B76A"/>
    </linearGradient>
    <filter id="blur3" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="6"/>
    </filter>
  </defs>

  <!-- Squircle background + overlays -->
  <rect width="1024" height="1024" rx="230" ry="230" fill="url(#bg)"/>
  <rect width="1024" height="560" rx="230" ry="230" fill="url(#topHi)"/>
  <ellipse cx="512" cy="276" rx="360" ry="160" fill="url(#dawnGlow)"/>

  <!-- Ground shadow -->
  <ellipse cx="512" cy="850" rx="336" ry="20" fill="#000" opacity="0.45" filter="url(#blur3)"/>

  <!-- Bottom tile (no rotation) -->
  <g>
    <rect x="176" y="716" width="672" height="124" rx="44" fill="#000" opacity="0.30" filter="url(#blur3)"/>
    <rect x="176" y="708" width="672" height="124" rx="44" fill="url(#tBtm)"/>
    <rect x="192" y="716" width="640" height="8" rx="4" fill="#ffffff" opacity="0.45"/>
  </g>

  <!-- Middle tile, -2.2° pivot (512, 606) -->
  <g transform="rotate(-2.2 512 606)">
    <rect x="248" y="552" width="528" height="124" rx="40" fill="#000" opacity="0.28" filter="url(#blur3)"/>
    <rect x="248" y="544" width="528" height="124" rx="40" fill="url(#tMid)"/>
    <rect x="264" y="552" width="496" height="8" rx="4" fill="#ffffff" opacity="0.55"/>
  </g>

  <!-- Upper tile, +1.8° pivot (512, 436) -->
  <g transform="rotate(1.8 512 436)">
    <rect x="324" y="384" width="376" height="120" rx="36" fill="#000" opacity="0.26" filter="url(#blur3)"/>
    <rect x="324" y="376" width="376" height="120" rx="36" fill="url(#tUpper)"/>
    <rect x="340" y="384" width="344" height="8" rx="4" fill="#ffffff" opacity="0.60"/>
  </g>

  <!-- Top tile, -1.5° pivot (512, 264) -->
  <g transform="rotate(-1.5 512 264)">
    <rect x="396" y="216" width="232" height="112" rx="32" fill="#000" opacity="0.25" filter="url(#blur3)"/>
    <rect x="396" y="208" width="232" height="112" rx="32" fill="url(#tTop)"/>
    <rect x="408" y="216" width="208" height="6" rx="3" fill="#ffffff" opacity="0.70"/>
  </g>
</svg>
```

- [ ] **Step 2: Eye-test the SVG**

Run: `open apps/Resources/AppIcon.svg`
Expected: macOS Preview shows the cairn icon — 4 tiles stacked, warm dawn glow behind the top tile, deep-blue squircle background. If tiles are misaligned or the background is flat, something copy-pasted wrong.

- [ ] **Step 3: Commit**

```bash
git add apps/Resources/AppIcon.svg
git commit -m "feat(icon): add master AppIcon.svg (geometric cairn)"
```

---

## Task 2: Author the render pipeline

**Files:**
- Create: `scripts/render-icon.sh`

- [ ] **Step 1: Write the script**

Create `scripts/render-icon.sh` with this content:

```bash
#!/usr/bin/env bash
# Render apps/Resources/AppIcon.svg → the 10 PNGs required by AppIcon.appiconset.
# Requires: rsvg-convert (brew install librsvg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/apps/Resources/AppIcon.svg"
OUT="$ROOT/apps/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. install with: brew install librsvg" >&2
  exit 1
fi

[[ -f "$SRC" ]] || { echo "error: missing SVG source at $SRC" >&2; exit 1; }
mkdir -p "$OUT"

render() {
  local px=$1 name=$2
  rsvg-convert -w "$px" -h "$px" -f png "$SRC" -o "$OUT/$name"
  # sanity-check output dimensions
  local got
  got="$(sips -g pixelWidth "$OUT/$name" | awk '/pixelWidth/ {print $2}')"
  if [[ "$got" != "$px" ]]; then
    echo "error: $name is ${got}px, expected ${px}px" >&2
    exit 1
  fi
  printf "  ✓ %-28s %dx%d\n" "$name" "$px" "$px"
}

echo "rendering AppIcon.appiconset …"
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png
echo "done."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/render-icon.sh`

- [ ] **Step 3: Commit (script only — we'll run it in Task 4)**

```bash
git add scripts/render-icon.sh
git commit -m "feat(icon): add render-icon.sh (svg → appiconset pipeline)"
```

---

## Task 3: Create the asset catalog skeleton

**Files:**
- Create: `apps/Resources/Assets.xcassets/Contents.json`
- Create: `apps/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Create the root catalog descriptor**

Create `apps/Resources/Assets.xcassets/Contents.json` with:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Create the AppIcon descriptor**

Create `apps/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` with:

```json
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/Resources/Assets.xcassets/Contents.json \
        apps/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
git commit -m "feat(icon): add Assets.xcassets with AppIcon slot"
```

---

## Task 4: Render and commit the PNGs

**Files:**
- Create (generated, 10 files): `apps/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png`

- [ ] **Step 1: Run the renderer**

Run: `./scripts/render-icon.sh`

Expected output (order + sizes):
```
rendering AppIcon.appiconset …
  ✓ icon_16x16.png               16x16
  ✓ icon_16x16@2x.png            32x32
  ✓ icon_32x32.png               32x32
  ✓ icon_32x32@2x.png            64x64
  ✓ icon_128x128.png             128x128
  ✓ icon_128x128@2x.png          256x256
  ✓ icon_256x256.png             256x256
  ✓ icon_256x256@2x.png          512x512
  ✓ icon_512x512.png             512x512
  ✓ icon_512x512@2x.png          1024x1024
done.
```

If `rsvg-convert` is missing: `brew install librsvg` then re-run.

- [ ] **Step 2: Verify all 10 files exist and none is zero bytes**

Run: `ls -la apps/Resources/Assets.xcassets/AppIcon.appiconset/*.png | awk '$5 == 0 {exit 1} END {print NR, "pngs ok"}'`
Expected: `10 pngs ok`

- [ ] **Step 3: Spot-check the 16 px render**

Run: `open apps/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png`
Expected: at this size, 4 tiles should still be distinguishable as 4 horizontal bands (spec acceptance criterion). If they blur into one blob, the SVG needs thicker separation — flag and stop.

- [ ] **Step 4: Commit the PNGs**

```bash
git add apps/Resources/Assets.xcassets/AppIcon.appiconset/*.png
git commit -m "feat(icon): render AppIcon PNGs (10 sizes)"
```

---

## Task 5: Wire `CFBundleIconName` via xcodegen

**Files:**
- Modify: `apps/project.yml` (add one key under `targets.Cairn.info.properties`)

- [ ] **Step 1: Add the property**

In `apps/project.yml`, locate the block:

```yaml
    info:
      path: Sources/Info.plist
      properties:
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 ongjin. MIT License."
```

Change it to:

```yaml
    info:
      path: Sources/Info.plist
      properties:
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 ongjin. MIT License."
        CFBundleIconName: AppIcon
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `(cd apps && xcodegen generate)`
Expected: `Loaded project` + `Created project at .../Cairn.xcodeproj` with no errors.

- [ ] **Step 3: Confirm the plist merge**

Run: `plutil -p apps/Sources/Info.plist | grep CFBundleIconName`
Expected: `"CFBundleIconName" => "AppIcon"` (xcodegen writes back into the plist file when it regenerates).

If the key isn't present, it means xcodegen merges into a synthesized plist at build time rather than the source file — continue to the build step anyway; the built app's `Info.plist` is the real test.

- [ ] **Step 4: Commit**

```bash
git add apps/project.yml apps/Sources/Info.plist
git commit -m "feat(icon): wire CFBundleIconName=AppIcon via project.yml"
```

---

## Task 6: Build and verify end-to-end

**Files:** (none — verification only)

- [ ] **Step 1: Build the app**

Run:
```bash
(cd apps && xcodebuild -scheme Cairn -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tail -20)
```
Expected: `** BUILD SUCCEEDED **` in the last lines.

- [ ] **Step 2: Locate the built bundle**

Run: `APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Cairn-*/Build/Products/Debug/Cairn.app | head -1); echo "$APP"`
Expected: path prints, not empty.

- [ ] **Step 3: Confirm the icon ended up in the bundle**

Run: `ls "$APP/Contents/Resources/" | grep -i icon`
Expected: `AppIcon.icns` appears in the list.

- [ ] **Step 4: Confirm the plist names it**

Run: `plutil -p "$APP/Contents/Info.plist" | grep -iE 'CFBundleIconName|CFBundleIconFile'`
Expected: `"CFBundleIconName" => "AppIcon"`.

- [ ] **Step 5: Visually verify in Finder**

Run: `open -R "$APP"`
Expected: Finder opens the enclosing folder with `Cairn.app` showing the new cairn icon thumbnail (not the generic white app icon).

- [ ] **Step 6: Visually verify in Dock**

Run: `open "$APP"`
Expected: The app launches and its Dock icon is the cairn icon. Quit with Cmd-Q.

- [ ] **Step 7: No-op commit if anything was re-generated**

Run: `git status`
If `apps/Sources/Info.plist` or `apps/Cairn.xcodeproj/` changed as a side effect of the regenerate/build, commit them:

```bash
git add apps/Sources/Info.plist apps/Cairn.xcodeproj
git commit -m "chore(icon): refresh plist/project after xcodegen"
```

Otherwise, skip this step.

---

## Acceptance check (mirrors spec)

- [ ] `apps/Resources/AppIcon.svg` committed and renders cleanly in Preview.
- [ ] `./scripts/render-icon.sh` re-runs cleanly and produces all 10 PNGs at correct dimensions.
- [ ] Asset catalog has exactly the 10 required entries, no gaps.
- [ ] Built `Cairn.app` shows the icon in Finder, Dock, and Cmd-Tab.
- [ ] At 16 px (Finder row thumbnail), all 4 tiles remain distinguishable.
