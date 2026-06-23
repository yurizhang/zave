#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) Zave.app, optional .zip / .dmg.
# Usage: ./packaging/package.sh [--zip] [--dmg]
set -euo pipefail

cd "$(dirname "$0")/.."

APP="Zave.app"
OUT="dist"
BIN="zig-out/bin/zave"
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
lipo -create /tmp/wf_arm64 /tmp/wf_x86 -output "${OUT}/${APP}/Contents/MacOS/zave"
chmod +x "${OUT}/${APP}/Contents/MacOS/zave"
[ -f packaging/icon.icns ] && cp packaging/icon.icns "${OUT}/${APP}/Contents/Resources/icon.icns" || true

# Ad-hoc sign (free, no Apple account): gives the app a stable identity so
# macOS remembers folder-access (TCC) grants instead of re-prompting.
codesign --force --deep --sign - "${OUT}/${APP}"

echo "      $(lipo -archs "${OUT}/${APP}/Contents/MacOS/zave")"
echo "Done: ${OUT}/${APP}"

for arg in "$@"; do
  case "$arg" in
    --zip)
      echo "[+] Building .zip ..."
      rm -f "${OUT}/zave.zip"
      # ditto preserves the .app bundle correctly (better than `zip` here)
      ditto -c -k --sequesterRsrc --keepParent "${OUT}/${APP}" "${OUT}/zave.zip"
      echo "Done: ${OUT}/zave.zip"
      ;;
    --dmg)
      echo "[+] Building .dmg ..."
      rm -f "${OUT}/zave.dmg"
      hdiutil create -volname "Zave" -srcfolder "${OUT}/${APP}" \
        -ov -format UDZO "${OUT}/zave.dmg" >/dev/null
      echo "Done: ${OUT}/zave.dmg"
      ;;
  esac
done

echo "Launch with:  open ${OUT}/${APP}"
