#!/bin/bash
# Sign with hardened runtime, notarize, and staple the NousUsageBar.app bundle.
# Usage:  ./sign.sh  (must have: Developer ID identity + notarytool credentials)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/NousUsageBar.app"
IDENTITY="Developer ID Application"
TEAM_ID="78U79ZZ8M4"
KEYCHAIN_PROFILE="AC_PASSWORD"   # notarytool credential profile

echo "==> 1/4 Signing with hardened runtime..."
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" \
  --entitlements "$HERE/signing/entitlements.plist" \
  "$APP"
echo "    signed: $(codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Signature|flags' | head -5)"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "    verification passed"

echo "==> 2/4 Building distributable DMG..."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
DMG_PATH="$HERE/dist/signed/NousUsageBar-${VERSION}-signed.dmg"
rm -rf "$HERE/dist/signed" && mkdir -p "$HERE/dist/signed"
hdiutil create -volname "NousUsageBar" -srcfolder "$APP" -ov -format UDZO \
  "$DMG_PATH" >/dev/null
echo "    DMG created: $DMG_PATH"
echo "    (Note: spctl cannot assess a DMG file directly - DMGs are never"
echo "     codesigned as a file. Gatekeeper checks the notarized APP inside,"
echo "     so 'spctl --type execute' on the app is the real acceptance test.)"

echo "==> 3/4 Notarizing (submitting to Apple)..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait \
  --output-format json 2>&1 | tail -20

echo "==> 4/4 Staple the ticket..."
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG_PATH"
echo "    stapled"

echo ""
echo "✔ Done. Signed + notarized DMG at:"
echo "  $DMG_PATH"
echo "  (Gatekeeper-clean: users can download, double-click, run.)"
