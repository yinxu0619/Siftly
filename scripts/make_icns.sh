#!/usr/bin/env bash
# Build assets/AppIcon.icns from a source PNG (default: assets/AppIcon-square.png).
#
# The source is cropped to a centered square, resized to standard icon sizes with
# `sips`, and the .icns container is assembled directly (no `iconutil`, which can
# fail in restricted/sandboxed environments that block the Darwin temp dir).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-assets/AppIcon-square.png}"
OUT="assets/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "source not found: $SRC" >&2
  exit 1
fi

WORK="$(pwd)/.build/iconpng"
rm -rf "$WORK"; mkdir -p "$WORK"

# Crop to a centered square at the smaller dimension.
W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
SIDE=$(( W < H ? W : H ))
sips -c "$SIDE" "$SIDE" "$SRC" --out "$WORK/square.png" >/dev/null

for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$WORK/square.png" --out "$WORK/$size.png" >/dev/null
done

python3 - "$WORK" "$OUT" <<'PY'
import struct, sys, os
work, out = sys.argv[1], sys.argv[2]
# OSType -> pixel size (PNG-based representations)
types = [("icp4",16),("ic11",32),("ic12",64),("ic07",128),
         ("ic08",256),("ic09",512),("ic10",1024)]
chunks = b""
for ostype, size in types:
    with open(os.path.join(work, f"{size}.png"), "rb") as f:
        data = f.read()
    chunks += ostype.encode("ascii") + struct.pack(">I", len(data) + 8) + data
icns = b"icns" + struct.pack(">I", len(chunks) + 8) + chunks
with open(out, "wb") as f:
    f.write(icns)
print(f"==> Wrote {out} ({len(icns)} bytes, {len(types)} sizes)")
PY
