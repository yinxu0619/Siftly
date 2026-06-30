# Siftly

A lightweight macOS media manager for photographers working directly on storage cards. Siftly uses a **lightweight index** — it never copies originals, operates on files in place, and stays memory-friendly on large SD / CFexpress cards.

Its standout feature is **RAW/JPG paired deletion by filename**: delete one file and matching companions are removed together. Deletions go to the macOS Trash by default (⌘Z undo), or you can **delete permanently** (skip Trash, irreversible).

**Languages:** English (default) and Simplified Chinese — follows your macOS system language automatically.

[中文文档](README.zh-Hans.md)

---

## Features

### Core
- Auto-detects removable SD / CFexpress volumes with hot-plug refresh
- Thumbnail grid for Sony ARW, Canon CR2/CR3, Nikon NEF/NRW, Fuji RAF, JPG/HEIC/PNG, and more
- **Multi-brand pairing presets**: Universal / Sony / Canon / Nikon / Fuji (toolbar link icon)
- **RAW/JPG paired deletion**: same base name + compatible extensions in one folder → delete one, delete all
- **Cross-card pairing**: browse all cards together; match by filename across cards (dual-slot RAW+JPG on separate cards)
- Batch delete with full confirmation list (selected + paired additions, per-card labels)
- **Two delete modes**: Move to Trash (undo with ⌘Z) or delete permanently

### Browse & view
- **Full-screen preview**: ←/→ or scroll wheel, pinch/double-click/⌘+/⌘- zoom, pan, ⌘0 fit, 0–5 rating, space to toggle selection, Delete, Esc/⌘W close
- **EXIF overlay** in preview (toggle with `I` or info button; preference remembered)
- **Selection**: click, ⌘+click, Shift+click range, marquee drag (⌘+drag to add)
- Context menu: preview, Reveal in Finder, open, rate, label, copy name/path, Trash
- Search, filter (All/RAW/JPG/Paired/Unpaired), rating/label filters, sort
- Batch: select all (⌘A / Ctrl+A), invert (⌘I), clear (⌘D), batch rating/labels

### Keyboard shortcuts
- **Grid**: ⌘A/Ctrl+A select all, ⌘I invert, ⌘D clear, Shift+click range, marquee, Delete/⌘⌫ Trash, ⌘Z undo
- **Preview**: ←/→ or scroll, space, 0–5 stars, `I` toggle EXIF, ⌘+/⌘-/⌘0 zoom, ⌘E edit, Delete, Esc/⌘W close
- **Editor**: ⌘W/Esc close; Return to finish crop

### Simple editing (non-destructive)
- Edit from context menu or preview — **originals are never modified**; export saves a new file
- Live preview for RAW (Core Image) and JPG/HEIC/PNG/TIFF
- Light, color, detail, tone curve, HDR
- Rotate, flip, straighten, **auto level** (Vision horizon), interactive crop with aspect presets
- Export / convert / compress: JPEG, HEIC, PNG, TIFF with quality and optional long-edge resize

### Marks & info
- Star ratings (0–5) and color labels, persisted in a sidecar index
- Inspector panel with EXIF (dimensions, camera, lens, ISO, aperture, shutter, focal length, date)

### About / Sponsor
- **Siftly → About Siftly** (Help menu removed)
- WeChat / Alipay QR codes + [PayPal](https://www.paypal.com/paypalme/yinxu0619)

### Performance
- Streaming scan — files appear as discovered
- Lazy thumbnails with ~256 MB memory cap
- **Preview prefetch cache** (Settings ⌘, — default 3 neighbors per side; 0 = off)
- O(n) pairing; batched background delete with progress

### Settings (⌘,)
- Prefetch adjacent photos (0–20 per side)

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+ (tested with Xcode 26, Swift 6.3)

## Build & run

```bash
swift build
swift run
swift test
```

If SwiftPM cannot write to the default cache (CI/sandbox), use:

```bash
chmod +x scripts/dev.sh
./scripts/dev.sh build
./scripts/dev.sh run
./scripts/dev.sh test
```

Grant **Full Disk Access** or **Files and Folders** in System Settings if scanning fails.

### Package as `.app`

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
open dist/Siftly.app
```

Output: `dist/Siftly.app` and `dist/Siftly.zip` (universal arm64 + x86_64). First launch may require right-click → Open if Gatekeeper blocks unsigned builds.

### Open in Xcode

```bash
open Package.swift
```

---

## Usage

1. Insert a card → select it in the sidebar → scan starts automatically.
2. Grid: click to select, ⌘+click multi-select, double-click preview, right-click for actions.
3. Delete: select files → Trash (or Delete) → review list → confirm. Toggle permanent delete if needed.
4. Undo: ⌘Z restores the last Trash deletion (not permanent deletes).
5. Edit: context menu or preview → adjust → Export to a new file.

### Cross-card dual-slot workflow

1. Insert both cards.
2. Select **All Storage Cards** (when ≥2 cards detected).
3. Pairing matches by filename across cards; deletion list shows which card each file is on.

> Camera filenames repeat across shoots — verify thumbnails and card names before cross-card delete.

### Pairing presets

| Preset | Extensions |
| --- | --- |
| Universal (default) | All supported RAW + jpg/jpeg/heic/heif |
| Sony | arw + JPG/HEIC |
| Canon | cr2/cr3 + JPG/HEIC |
| Nikon | nef/nrw + JPG/HEIC |
| Fuji | raf + JPG/HEIC |

---

## Architecture

| Layer | Path | Key types |
| --- | --- | --- |
| Scan | `Sources/SiftlyKit/DiskScan` | `Volume`, `MediaFile` |
| Pairing | `Sources/SiftlyKit/Pairing` | `PairingRule`, `PairingEngine`, `DeletionPlanner` |
| Editing | `Sources/SiftlyKit/Editing` | `ImageAdjustments`, `ImageProcessor`, `ExportSettings` |
| Platform | `Sources/SiftlyKit/Platform` | `VolumeService`, `FileSystemService`, `TrashService`, `ThumbnailService` |
| UI | `Sources/SiftlyKit/UI` | SwiftUI views |
| Localization | `Sources/SiftlyKit/Localization` | `L10n`, `Resources/Localizable.xcstrings` |
| App | `Sources/SiftlyKit/App` | `AppState`, `SiftlyApp` |

`SiftlyKit` is a library (testable); `Siftly` is a thin executable host.

---

## Localization

- Source language: **English** (`defaultLocalization: "en"` in `Package.swift`)
- Translations: `Sources/SiftlyKit/Resources/Localizable.xcstrings` (Simplified Chinese included)
- UI strings go through `L10n` in `Sources/SiftlyKit/Localization/L10n.swift`
- To add a locale: add translations to the `.xcstrings` catalog

---

## Tests

```bash
swift test
```

Covers pairing, deletion planning, scanning, editing models, and utilities.

---

## Sponsor

If Siftly helps your workflow, consider buying the author a coffee ☕️

<table>
  <tr>
    <td align="center"><b>WeChat</b></td>
    <td align="center"><b>Alipay</b></td>
  </tr>
  <tr>
    <td align="center"><img src="assets/sponsor-wechat.png" width="240" alt="WeChat Pay"></td>
    <td align="center"><img src="assets/sponsor-alipay.png" width="240" alt="Alipay"></td>
  </tr>
</table>

**PayPal:** [paypal.me/yinxu0619](https://www.paypal.com/paypalme/yinxu0619)
