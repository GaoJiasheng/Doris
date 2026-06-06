#!/usr/bin/env bash
# Package the already-notarized + stapled Doris.app (produced by
# scripts/release-mac-zip.sh) into a notarized + stapled DMG for direct
# distribution. The DMG container is notarized too so it mounts silently
# on a fresh Mac (no Gatekeeper "verifying" spinner the first time).
#
# Run release-mac-zip.sh FIRST — this script reuses its notarized app at
#   build/release-<version>/zip-staging/Doris.app
#
# Output: build/release-<version>/Doris-<version>.dmg
#
# Deps: create-dmg, pandoc, Google Chrome (HTML→PDF for the CLI manual).

set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${DORIS_NOTARY_PROFILE:-doris-notary}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

command -v create-dmg >/dev/null || { echo "❌ create-dmg missing (brew install create-dmg)"; exit 1; }
command -v pandoc     >/dev/null || { echo "❌ pandoc missing (brew install pandoc)"; exit 1; }
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "❌ Google Chrome missing — needed for the CLI manual PDF"; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --keychain "$LOGIN_KEYCHAIN" >/dev/null 2>&1 \
  || { echo "❌ notary keychain profile '$NOTARY_PROFILE' missing"; exit 1; }

VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | awk -F'"' '{print $2}')"
: "${VERSION:?Could not parse MARKETING_VERSION}"

BUILD_DIR="build/release-$VERSION"
APP="$BUILD_DIR/zip-staging/Doris.app"
DMG="$BUILD_DIR/Doris-$VERSION.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"

[ -d "$APP" ] || { echo "❌ notarized app missing at $APP — run scripts/release-mac-zip.sh first"; exit 1; }
xcrun stapler validate "$APP" >/dev/null 2>&1 || { echo "❌ $APP isn't notarized/stapled — run release-mac-zip.sh"; exit 1; }

echo "📦 Packaging Doris $VERSION DMG from the notarized app..."
rm -rf "$DMG_STAGING" "$DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"

echo "📄 Rendering CLI manual to PDF..."
TMP_HTML="$BUILD_DIR/cli-manual.html"
pandoc docs/cli-manual.md \
  --standalone \
  --metadata title="Doris CLI Manual" \
  --to html5 \
  --css=scripts/cli-manual-print.css \
  --embed-resources \
  -o "$TMP_HTML" 2>&1 | tail -2
"$CHROME" \
  --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$DMG_STAGING/CLI Manual.pdf" \
  "file://$PWD/$TMP_HTML" 2>&1 | tail -1
[ -s "$DMG_STAGING/CLI Manual.pdf" ] || { echo "❌ empty PDF"; exit 1; }
echo "   ✓ PDF ($(du -h "$DMG_STAGING/CLI Manual.pdf" | cut -f1))"

echo "💿 Building DMG..."
create-dmg \
  --volname "Doris $VERSION" \
  --window-size 600 400 \
  --icon-size 96 \
  --icon "Doris.app" 140 180 \
  --icon "CLI Manual.pdf" 300 180 \
  --app-drop-link 460 180 \
  --no-internet-enable \
  "$DMG" \
  "$DMG_STAGING" 2>&1 | tail -5

[ -f "$DMG" ] || { echo "❌ DMG not produced"; exit 1; }

# Codesign the DMG *wrapper* (Developer ID) before notarizing. The app
# inside is already signed+notarized+stapled; signing the container too
# means `spctl --assess` blesses the .dmg offline ("Notarized Developer
# ID") instead of reporting "no usable signature". Sign BEFORE notarize
# so the ticket covers the signed bytes. No --options=runtime (that's
# for executables, not disk images).
IDENTITY="${DORIS_DEVID_IDENTITY:-Developer ID Application: Gavin Gao (D33974QQTD)}"
echo "✍️  Codesigning the DMG wrapper..."
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "🍎 Notarizing DMG (5-15 min)..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" --keychain "$LOGIN_KEYCHAIN" \
  --wait --output-format normal 2>&1 | tee "$BUILD_DIR/notary-dmg.log"
grep -q "status: Accepted" "$BUILD_DIR/notary-dmg.log" \
  || { echo "❌ DMG notarization not Accepted — see $BUILD_DIR/notary-dmg.log"; exit 1; }

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" 2>&1 | tail -1
spctl --assess --type install --verbose "$DMG" 2>&1 | tail -2 || true

echo ""
echo "✨ DMG built: $DMG ($(du -h "$DMG" | cut -f1))"
echo "   Notarized + stapled — mounts silently on any Mac."
