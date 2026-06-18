#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) window-finder.app and optionally a .dmg.
# Usage: ./packaging/package.sh [--dmg]
set -euo pipefail

cd "$(dirname "$0")/.."

APP="window-finder.app"
OUT="dist"
BIN="zig-out/bin/filemanager"
SDK="$(xcrun --show-sdk-path)"

# NOTE: build arm64 natively (no -Dtarget) so Zig auto-detects the SDK;
# an explicit -Dtarget is treated as a cross build and loses that detection.
echo "[1/4] Building arm64 (Apple Silicon)..."
zig build -Doptimize=ReleaseFast
cp "${BIN}" /tmp/wf_arm64

echo "[2/4] Building x86_64 (Intel)..."
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos -Dmacos-sdk="${SDK}"
cp "${BIN}" /tmp/wf_x86

echo "[3/4] Assembling universal ${APP} ..."
rm -rf "${OUT:?}/${APP}"
mkdir -p "${OUT}/${APP}/Contents/MacOS" "${OUT}/${APP}/Contents/Resources"
cp packaging/Info.plist "${OUT}/${APP}/Contents/Info.plist"
lipo -create /tmp/wf_arm64 /tmp/wf_x86 -output "${OUT}/${APP}/Contents/MacOS/window-finder"
chmod +x "${OUT}/${APP}/Contents/MacOS/window-finder"
[ -f packaging/icon.icns ] && cp packaging/icon.icns "${OUT}/${APP}/Contents/Resources/icon.icns" || true
echo "      $(lipo -archs "${OUT}/${APP}/Contents/MacOS/window-finder")"
echo "Done: ${OUT}/${APP}"

if [ "${1:-}" = "--dmg" ]; then
  echo "[4/4] Building .dmg ..."
  rm -f "${OUT}/window-finder.dmg"
  hdiutil create -volname "window-finder" -srcfolder "${OUT}/${APP}" \
    -ov -format UDZO "${OUT}/window-finder.dmg" >/dev/null
  echo "Done: ${OUT}/window-finder.dmg"
fi

echo "Launch with:  open ${OUT}/${APP}"
