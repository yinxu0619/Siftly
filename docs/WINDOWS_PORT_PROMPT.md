# Prompt: Build the Windows version of Siftly (Tauri)

> Paste everything below this line into an AI coding agent (e.g. Cursor) running on
> your **Windows** machine, inside an empty folder. It is a complete, self-contained
> spec. The existing macOS app is written in Swift/SwiftUI; this is a **fresh
> cross-platform rewrite in Tauri**, not a port of the Swift code.

---

## Role & goal

You are building **Siftly for Windows**: a lightweight desktop app for photographers
to cull and lightly edit photos **directly on camera storage cards** (SD / CFexpress),
operating on the original files in place (never copying them into a library).

Build it with **Tauri 2** (Rust backend + web frontend). The final deliverable MUST be
a **standalone Windows app**: a `Siftly.exe` plus an installer (`.msi` and/or NSIS
`.exe`). The end user double-clicks it like any normal program — **no command line, no
dev server, no browser, no localhost port**. The web UI renders inside an embedded
**WebView2** window (preinstalled on Windows 10/11; configure the installer to
auto-download it if missing).

A polished macOS version already exists at https://github.com/yinxu0619/Siftly — match
its behavior and feel. Aim for **full feature parity** (browsing, pairing-aware
deletion, preview, non-destructive editor, settings, about/sponsor, i18n).

## Tech stack (use these)

- **Tauri 2** (`tauri`, `tauri-build`, `@tauri-apps/cli`, `@tauri-apps/api`).
- **Frontend**: React + TypeScript + Vite + Tailwind CSS. State via Zustand (or
  Context). i18n via `i18next` + `react-i18next`.
- **Backend (Rust)** crates:
  - `walkdir` — fast recursive scan.
  - `image` — decode/encode JPEG/PNG/TIFF/WEBP/BMP/GIF and run pixel adjustments.
  - `kamadak-exif` — read EXIF/TIFF metadata.
  - `rawler` (or `libraw`/`libraw-sys` via vcpkg) — decode RAW (ARW/CR2/CR3/NEF/RAF…)
    to RGB for thumbnails, preview, and editing. If a RAW format fails, fall back to
    the embedded JPEG preview extracted from the RAW (most cameras embed one — use
    `image`/exif to locate it). Always have a graceful fallback.
  - `trash` — move files to the Windows Recycle Bin (cross-platform).
  - `serde` / `serde_json`, `rayon` (parallel thumbnailing), `fast_image_resize`
    (quality downscaling), `notify` (optional: hot-plug/drive change detection).
- **Drive detection (Windows)**: enumerate logical drives and keep those whose
  `GetDriveTypeW` == `DRIVE_REMOVABLE` (use the `windows` crate). Show volume label
  + free/total size. Provide a way to also add any folder manually (for testing on a
  PC without a card).

> Keep all heavy work (scan, RAW decode, thumbnailing, editing, export) in Rust,
> invoked from the UI via Tauri commands, and run it off the UI thread (async /
> `tauri::async_runtime` / rayon). The UI must stay responsive on cards with
> thousands of files.

---

## Data model (port these exactly)

### Media file
```
MediaFile {
  path: string (absolute)
  name: string                 // file name with extension
  base_name: string            // name without extension (pairing key)
  ext: string                  // lowercased, no dot
  directory: string
  file_size: u64
  modified: i64 (unix seconds)
  volume_id: string            // stable per drive (e.g. volume serial)
  volume_name: string
  volume_path: string          // drive root, e.g. "E:\\"
  is_raw: bool                 // ext ∈ RAW set below
}
```

### Known extensions
```
RAW   = arw cr2 cr3 nef nrw raf rw2 orf dng pef srw x3f raw 3fr erf mef
JPEG  = jpg jpeg
OTHER = png heic heif tiff tif gif bmp webp
IMAGE = RAW ∪ JPEG ∪ OTHER   // scanner includes all of these
```

### Pairing rules
Two files **pair** when they are in the **same directory**, share the **same base
name** (case-insensitive), and their extensions are in the **same group**. Presets
(the user picks one in the toolbar; default = Universal):

```
companions = [jpg, jpeg, heic, heif]
Universal  groups = [ RAW ∪ companions ]      // default; any RAW pairs with JPG/HEIC
Sony       groups = [ [arw] ∪ companions ]
Canon      groups = [ [cr2, cr3] ∪ companions ]
Nikon      groups = [ [nef, nrw] ∪ companions ]
Fuji       groups = [ [raf] ∪ companions ]
```

**Cross-card pairing**: when the user browses **"All Storage Cards"**, set a
`cross_location` flag that makes pairing ignore the directory/drive and match purely
by base name + group. This links dual-slot setups where RAW is on one card and JPG on
another (e.g. deleting `DSC00370.ARW` on card A also deletes `DSC00370.JPG` on card B).

**Pairing algorithm** (O(n) bucketing): build `ext -> group_index`; bucket each file by
key `"{location}\u0}{group_index}\u0}{base_lower}"` where `location` is the directory
path normally, or `""` when `cross_location`. Any bucket with >1 file means all files in
it are mutual partners.

**Deletion plan**: given a set of selected paths, expand to include every partner of
each selected file (deduplicated). Present two groups in the confirm dialog:
`directly_selected` and `paired_additions` (the auto-added partners), each sorted by
name, with per-file size and a combined total. Deleting one of a pair deletes them all.

### Marks (ratings + labels), persisted as a sidecar index
```
Rating = 0..5 (none..5 stars)
ColorLabel = none red orange yellow green blue purple gray
FileMark { rating: Rating, label: ColorLabel }   // omit when both are none
```
Persist as JSON `{ key: FileMark }` in the app data dir
(`%APPDATA%\Siftly\marks.json`). **Key = `"{volume_id}::{path-relative-to-volume}"`**
so marks follow a card across remounts. Never modify or copy the originals.

---

## Backend commands (Tauri `#[command]`s to expose)

- `list_volumes() -> Vec<Volume>` and emit an event on drive add/remove.
- `add_manual_folder(path) -> Volume` (treat a folder as a pseudo-volume for testing).
- `scan(volume_or_all) -> stream/Vec<MediaFile>` — recursive, includes all IMAGE exts.
  Stream results so the grid fills progressively.
- `compute_pairs(files, rule, cross_location) -> map<path, [partner paths]>`.
- `thumbnail(path, px) -> bytes(JPEG/PNG)` — small (e.g. 320px) for the grid; disk-cache
  by `(path, size, mtime)` under `%LOCALAPPDATA%\Siftly\thumbs`. RAW: decode via rawler
  or use embedded preview; orient via EXIF.
- `preview(path, px) -> bytes` — larger (e.g. 2600px) for the full-screen viewer; cache
  in memory with an LRU sized by the prefetch setting; support prefetch of neighbors.
- `read_exif(path) -> Exif` (see fields below).
- `plan_deletion(selected, rule, cross_location) -> DeletionPlan`.
- `delete(paths, permanent: bool)` — `permanent=false` → Recycle Bin (`trash` crate),
  `permanent=true` → hard delete. Report progress; support undo for the last
  Recycle-Bin batch where the OS allows it.
- `set_mark(key, mark)` / `get_marks()`.
- `render_preview(path, adjustments, max_dim, include_crop) -> bytes` — live editor.
- `auto_straighten(path) -> Option<degrees>` — detect horizon and return leveling angle
  in [-45,45]. (No Windows equivalent of Apple Vision; implement a simple detector:
  downscale → grayscale → Canny/Sobel edges → Hough transform → dominant near-horizontal
  line → angle. If unsure, return None. This is a nice-to-have; ship without it if
  needed and just keep the manual Straighten slider.)
- `export(path, adjustments, settings, dest)` — full-res render + encode.

### EXIF fields to read & display
`pixel_width, pixel_height, camera_make, camera_model, lens_model, iso, aperture
(f-number), shutter_speed (format `1/Ns` when <1s, else `N.Ns`), focal_length,
date_taken`. Show "W × H" as a dimension string.

---

## Non-destructive editor (match the macOS math)

Adjustments struct (friendly UI units; defaults 0 unless noted):
```
Light:  exposure[-100..100], brightness[-100..100], contrast[-100..100],
        highlights[-100..100], shadows[-100..100], hdr[0..100]
Color:  saturation[-100..100], vibrance[-100..100], temperature[-100..100],
        tint[-100..100]
Detail: sharpen[0..100], vignette[0..100]
Curve:  tone curve (RGB master), control points in 0..1 (identity = [(0,0),(1,1)])
Geometry: rotation_quarters[0..3] (clockwise 90°), straighten[-45..45 deg],
          flip_horizontal(bool), crop_rect (normalized 0..1, top-left origin, optional)
```

**Pipeline order & mapping** (apply each stage only when non-neutral; implement these
as pixel operations on a linear-ish/sRGB buffer with `image`, or via a shader if you
prefer — match the *intent* and rough strength below):

1. **Exposure**: multiply by `2^(exposure/100 * 2)` (EV ±2 at the extremes).
2. **Highlights/Shadows + HDR tone**: let `hdrK = hdr/100`.
   - `shadowAmount = clamp(shadows/100 + hdrK*0.6, -1, 1)` → lift shadows (local).
   - `highlightAmount = clamp(1 + min(0,highlights)/100*0.8 - hdrK*0.5, 0, 1)` → recover
     highlights (1 = unchanged, lower darkens highlights). Use a radius≈8 local
     highlight/shadow operator (e.g. blur-based luminance mask).
3. **White balance**: temperature/tint. Warmer for positive temperature, cooler for
   negative; tint negative→green, positive→magenta. (Reference used neutral 6500K with
   `target = 6500 + temperature*30`, tint as y.)
4. **Brightness/Contrast/Saturation**: `brightness += brightness/100*0.3`,
   `contrast *= 1 + contrast/100*0.5`, `saturation *= 1 + saturation/100`.
5. **Vibrance**: saturate less-saturated pixels more (`amount = vibrance/100`).
6. **Tone curve**: sample the curve (piecewise-linear through sorted points, clamped to
   first/last outside the range) into a 128-entry LUT applied equally to R/G/B.
7. **HDR local-contrast pop**: when `hdrK>0`, unsharp mask at large radius (≈12),
   `intensity = hdrK*0.8`.
8. **Sharpen**: luminance sharpen, `sharpness = sharpen/100`.
9. **Vignette**: darken edges, `intensity = vignette/100*1.5`, radius≈1.5.

**Geometry order**: 90° rotation → horizontal flip → straighten (rotate by degrees,
then auto-inscribe the largest centered axis-aligned rectangle to drop empty corners)
→ user crop (normalized rect). For the crop UI, render the straightened image WITHOUT
the user crop and draw an interactive crop box (with aspect presets: Free, Original,
1:1, 3:2, 4:3, 16:9; plus rotate/flip buttons, a straighten slider, and an
auto-level button).

**Export settings**:
```
format: jpeg | heic | png | tiff    (HEIC may be hard on Windows — if so, disable HEIC
                                      and keep jpeg/png/tiff; document the limitation)
quality: 0..1 (jpeg/heic only; default 0.9)
max_long_edge: optional resize presets = [Original, 4096, 3000, 2048, 1600, 1080]
```
Editing is non-destructive: originals are never changed; export writes a NEW file
(default next to the original or to a user-chosen path). Live preview should re-run
only the cheap filter chain on a downscaled cached source so sliders feel instant; the
RAW decode result should be cached and reused.

---

## UI (match the macOS app)

Three-pane layout:
- **Left sidebar**: "All Storage Cards" (cross-card mode) + each detected card with
  label and capacity; refresh button; a way to add a manual folder.
- **Center**: a filter/sort bar above a virtualized **thumbnail grid** (must handle
  thousands of items smoothly). Each cell shows the thumbnail, filename, a RAW badge, a
  link badge when paired, rating stars, and color label dot.
- **Right inspector**: file info + EXIF for the current file.

### Filter / sort bar
- Search box (filter by name).
- Format filter: **All / RAW / JPG / Paired / Unpaired**.
- Minimum rating filter (0–5) and color-label filter.
- Sort by **Date / Name / Size**, ascending/descending toggle.
- Pairing rule picker (Universal/Sony/Canon/Nikon/Fuji).
- A count + "clear filters" affordance.

### Selection (in grid)
- Click select, Ctrl+Click toggle, **Shift+Click range**, **marquee/box drag** (drag on
  empty space to rubber-band select; Ctrl+drag adds to selection).
- Select all (**Ctrl+A**), invert (**Ctrl+I**), clear (**Ctrl+D**).
- Batch apply rating/label to the selection.

### Full-screen preview
- Open on double-click. Navigate with **←/→ and mouse wheel**.
- Zoom: Ctrl+= / Ctrl+- / pinch, pan when zoomed, **Ctrl+0** fit.
- **0–5** set rating, **Space** toggle selection in/out of the cull set.
- **EXIF overlay** toggle with **I** (remember the on/off preference).
- Open the editor (**Ctrl+E**), delete, **Esc/Ctrl+W** to close.

### Right-click context menu (grid + preview)
Preview, Reveal in File Explorer, Open with default app, set rating, set label, copy
name, copy path, Move to Recycle Bin, Delete permanently.

### Delete confirmation dialog
Show the two-group plan (selected + paired additions) with per-file sizes and the
combined total, a clear note when **cross-card** mode is active ("pairs by filename;
verify files on different cards are truly the same photo"), and a checkbox **"Delete
permanently (skip Recycle Bin, cannot undo)"**. Default action = Move to Recycle Bin.

### Keyboard shortcuts (summary)
- Grid: Ctrl+A select all, Ctrl+I invert, Ctrl+D clear, Shift+Click range, marquee,
  Delete / Ctrl+Backspace → Recycle Bin, Ctrl+Z undo last delete.
- Preview: ←/→ or wheel, Space, 0–5 stars, I toggle EXIF, Ctrl+=/Ctrl+-/Ctrl+0 zoom,
  Ctrl+E edit, Delete, Esc/Ctrl+W close.
- Editor: Ctrl+W/Esc close; Enter to finish crop.

### Settings
- **Language**: Follow system / English / 简体中文 (override the OS language at runtime).
- **Preview prefetch count** (0–20 per side; default 3): how many neighbors to decode in
  the background around the viewed photo for instant flipping. Show a hint about memory
  use. Size the preview LRU cache from this value.

### About / Sponsor
An About dialog with app name/description and a **Sponsor** section: WeChat and Alipay
QR images, and a PayPal link `https://www.paypal.com/paypalme/yinxu0619`. (Copy the QR
images from the macOS repo's resources; if unavailable, leave labeled placeholders.)

### i18n
English (default) + Simplified Chinese, following the system locale, **overridable in
Settings**. Centralize strings in i18next resource files. Translate every user-facing
string. Numbers/sizes should format per the active locale.

---

## Build & distribution (the important part)

1. Initialize: `npm create tauri-app@latest` (React + TypeScript template) or set up
   Vite + React manually and add Tauri.
2. `tauri.conf.json`:
   - product name `Siftly`, an app icon (`tauri icon path/to/icon.png` generates the
     `.ico`/icon set — reuse the macOS app's icon art if available).
   - `bundle.targets`: `["msi", "nsis"]`.
   - Configure **WebView2** install mode so end users without it get it automatically
     (e.g. `downloadBootstrapper`), so the app "just works" on a clean Windows install.
   - Set filesystem/dialog/shell capabilities (permissions) needed for picking folders,
     revealing in Explorer, and opening files with the default app.
3. **Dev** (you, while building): `npm run tauri dev`.
4. **Release build** (what you ship): `npm run tauri build` → produces
   `src-tauri/target/release/Siftly.exe` and installers under
   `src-tauri/target/release/bundle/{msi,nsis}/`. This is a normal Windows app —
   double-click to install/run; no terminal, no browser.
5. Add a **GitHub Actions** workflow (`windows-latest` runner) that runs `tauri build`
   and uploads the `.msi`/`.exe` as artifacts (and optionally attaches them to a
   Release) so builds are reproducible without a local toolchain.

## Acceptance criteria

- Launching the built `.exe` opens a native window (WebView2), with **no console window
  and no browser**.
- Inserting a card (or adding a manual folder) lists it; scanning shows thumbnails for
  JPG **and** RAW (ARW/CR2/CR3/NEF/RAF at minimum), progressively and responsively for
  1000s of files.
- RAW/JPG **paired deletion** works (same base name): deleting one offers to delete its
  partners; the confirm dialog shows selected vs. paired additions with sizes/total.
- **Cross-card** mode pairs by filename across drives.
- Move to **Recycle Bin** (default, undoable where possible) and **permanent delete**
  both work.
- Ratings/labels persist across restarts via the sidecar JSON, keyed per volume.
- Full-screen preview with wheel/arrow navigation, zoom/pan, EXIF overlay toggle.
- The **editor** applies the adjustments above with live preview and exports a new file;
  originals are untouched.
- Settings language switch updates the UI live; English + 简体中文 both complete.
- `tauri build` produces a working `.msi`/`.exe` installer.

## Suggested project structure
```
siftly-win/
  src/                      # React + TS frontend
    components/ (Sidebar, FilterBar, Grid, ThumbnailCell, Inspector,
                Preview, Editor, CropOverlay, CurveEditor, DeleteDialog,
                Settings, About)
    store/      (Zustand state: volumes, files, selection, pairing, filters,
                preview/editor/dialog state, marks, settings)
    i18n/       (en.json, zh-Hans.json, index.ts)
    lib/        (tauri command wrappers, types, formatters)
  src-tauri/
    src/ (main.rs, commands/, scan.rs, pairing.rs, thumbs.rs, raw.rs,
          edit/ (pipeline.rs, geometry.rs, curve.rs), exif.rs, marks.rs,
          volumes.rs, trash.rs, export.rs)
    tauri.conf.json, Cargo.toml, icons/
  .github/workflows/build-windows.yml
  README.md
```

Build incrementally and keep it compiling: (1) scaffold + window, (2) volumes + scan +
grid thumbnails, (3) pairing + deletion + marks, (4) preview, (5) editor + export,
(6) settings + i18n + about, (7) installer + CI. Prioritize the cull workflow
(browse → pair → delete) first, then the editor.
