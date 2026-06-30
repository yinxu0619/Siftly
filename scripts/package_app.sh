#!/usr/bin/env bash
# Build Siftly and wrap the release binary into a double-clickable macOS .app
# bundle at dist/Siftly.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Siftly"
BUNDLE_ID="com.siftly.app"
VERSION="1.0"
CONFIG="release"

# Keep SwiftPM scratch/cache inside the repo (works in restricted environments).
SPM_FLAGS=(
  --disable-sandbox
  --scratch-path .build
  --cache-path .build/_cache
  --config-path .build/_config
  --security-path .build/_security
)

# Build a universal binary by default (Apple Silicon + Intel) so the app runs on
# any Mac. Set UNIVERSAL=0 to build only for the current architecture.
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building ${APP_NAME} (${CONFIG})…"
swift build -c "$CONFIG" "${SPM_FLAGS[@]}" "${ARCH_FLAGS[@]}"

BIN_PATH="$(swift build -c "$CONFIG" "${SPM_FLAGS[@]}" "${ARCH_FLAGS[@]}" --show-bin-path)"

APP_DIR="dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Assembling bundle at ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

# Copy any SwiftPM resource bundles (e.g. Siftly_SiftlyKit.bundle) so that
# Bundle.module can find them at runtime (icons, QR codes, etc.).
shopt -s nullglob
for bundle in "${BIN_PATH}"/*.bundle; do
  echo "==> Bundling resources: $(basename "$bundle")"
  cp -R "$bundle" "${CONTENTS}/Resources/"
done
shopt -u nullglob

# App icon: build from source if needed, then bundle it.
ICON_LINE=""
if [[ ! -f assets/AppIcon.icns && -f assets/AppIcon-square.png ]]; then
  ./scripts/make_icns.sh assets/AppIcon-square.png || true
fi
if [[ -f assets/AppIcon.icns ]]; then
  cp assets/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"
  ICON_LINE="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

cat > "${CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
${ICON_LINE}
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
</dict>
</plist>
EOF

# Ad-hoc code signature so macOS lets it launch locally.
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
  echo "   (codesign skipped/failed — app will still run; you may need to right-click > Open the first time)"

# Zip for distribution (preserves the bundle structure / signature).
echo "==> Creating distributable zip…"
ZIP_PATH="dist/${APP_NAME}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Done: ${APP_DIR}"
echo "    Architectures: $(lipo -archs "${CONTENTS}/MacOS/${APP_NAME}" 2>/dev/null || echo unknown)"
echo "    Zip:  ${ZIP_PATH}"
echo "    Double-click it in Finder, or run: open \"${APP_DIR}\""
