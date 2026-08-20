#!/bin/bash
# Build NousUsageBar.app and a distributable .dmg + .zip.
# Usage: ./build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP_NAME="NousUsageBar"
APP_DIR="$HOME/Applications/$APP_NAME.app"
DIST_DIR="$HERE/dist"
ICON_SOURCE="$HERE/assets/appicon-source.png"

echo "==> 1/5 Compiling Swift..."
xcrun swiftc -O -o "$APP_NAME" "$APP_NAME.swift" -framework AppKit

echo "==> 2/5 Preparing iconset -> AppIcon.icns"
if [ -f "$ICON_SOURCE" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_SOURCE" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$ICON_SOURCE" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$HERE/assets/AppIcon.icns"
fi

echo "==> 3/5 Assembling .app bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$APP_NAME" "$APP_DIR/Contents/MacOS/"
cp Info.plist "$APP_DIR/Contents/"
cp fetch_nous_usage.py "$APP_DIR/Contents/Resources/"
[ -f "$HERE/assets/AppIcon.icns" ] && cp "$HERE/assets/AppIcon.icns" "$APP_DIR/Contents/Resources/"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

echo "==> 4/5 Ad-hoc signing"
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1
codesign --verify --deep "$APP_DIR" && echo "    signature verified"

echo "==> 5/5 Creating DMG + ZIP"
rm -rf "$DIST_DIR" && mkdir -p "$DIST_DIR"
VOL="$APP_NAME-$(date +%Y%m%d)"
hdiutil create -volname "$VOL" -srcfolder "$APP_DIR" -ov -format UDZO \
  "$DIST_DIR/$VOL.dmg" >/dev/null
( cd "$DIST_DIR" && ditto -c -k --keepParent "$APP_DIR" "$VOL.zip" )

echo ""
echo "Done. Artifacts:"
echo "  App : $APP_DIR"
echo "  DMG : $DIST_DIR/$VOL.dmg"
echo "  ZIP : $DIST_DIR/$VOL.zip"
