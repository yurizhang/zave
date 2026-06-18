#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) window-finder.app, optional .zip / .dmg.
# Usage: ./packaging/package.sh [--zip] [--dmg]
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

# Ad-hoc sign (free, no Apple account): gives the app a stable identity so
# macOS remembers folder-access (TCC) grants instead of re-prompting.
codesign --force --deep --sign - "${OUT}/${APP}"

echo "      $(lipo -archs "${OUT}/${APP}/Contents/MacOS/window-finder")"
echo "Done: ${OUT}/${APP}"

for arg in "$@"; do
  case "$arg" in
    --zip)
      echo "[+] Building .zip ..."
      rm -f "${OUT}/window-finder.zip"
      # ditto preserves the .app bundle correctly (better than `zip` here)
      ditto -c -k --sequesterRsrc --keepParent "${OUT}/${APP}" "${OUT}/window-finder.zip"
      echo "Done: ${OUT}/window-finder.zip"
      ;;
    --dmg)
      echo "[+] Building .dmg ..."
      rm -f "${OUT}/window-finder.dmg"
      hdiutil create -volname "window-finder" -srcfolder "${OUT}/${APP}" \
        -ov -format UDZO "${OUT}/window-finder.dmg" >/dev/null
      echo "Done: ${OUT}/window-finder.dmg"
      ;;
  esac
done

echo "Launch with:  open ${OUT}/${APP}"
