#!/usr/bin/env bash
# Convenience wrapper around SwiftPM.
#
# In normal use you can just run `swift build` / `swift run` / `swift test`.
# This script keeps all SwiftPM scratch/cache state inside the repo, which is
# handy in restricted/CI environments where the default ~/Library caches are not
# writable.
set -euo pipefail

CMD="${1:-build}"
shift || true

SPM_FLAGS=(
  --scratch-path .build
  --cache-path .build/_cache
  --config-path .build/_config
  --security-path .build/_security
)

case "$CMD" in
  build) swift build "${SPM_FLAGS[@]}" "$@" ;;
  run)   swift run   "${SPM_FLAGS[@]}" "$@" ;;
  test)  swift test  "${SPM_FLAGS[@]}" "$@" ;;
  *) echo "usage: $0 {build|run|test} [extra swift flags]" >&2; exit 1 ;;
esac
