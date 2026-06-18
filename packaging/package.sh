#!/usr/bin/env bash
# Build window-finder.app (and optionally a .dmg) from a release binary.
# Usage: ./packaging/package.sh [--dmg]
set -euo pipefail

cd "$(dirname "$0")/.."

APP="window-finder.app"
OUT="dist"
BIN="zig-out/bin/filemanager"

echo "[1/3] Building release binary..."
zig build -Doptimize=ReleaseFast

echo "[2/3] Assembling ${APP} ..."
rm -rf "${OUT:?}/${APP}"
mkdir -p "${OUT}/${APP}/Contents/MacOS" "${OUT}/${APP}/Contents/Resources"
cp packaging/Info.plist "${OUT}/${APP}/Contents/Info.plist"
cp "${BIN}" "${OUT}/${APP}/Contents/MacOS/window-finder"
chmod +x "${OUT}/${APP}/Contents/MacOS/window-finder"
if [ -f packaging/icon.icns ]; then
  cp packaging/icon.icns "${OUT}/${APP}/Contents/Resources/icon.icns"
fi

echo "Done: ${OUT}/${APP}"

if [ "${1:-}" = "--dmg" ]; then
  echo "[3/3] Building .dmg ..."
  rm -f "${OUT}/window-finder.dmg"
  hdiutil create -volname "window-finder" -srcfolder "${OUT}/${APP}" \
    -ov -format UDZO "${OUT}/window-finder.dmg" >/dev/null
  echo "Done: ${OUT}/window-finder.dmg"
fi

echo "Launch with:  open ${OUT}/${APP}"
