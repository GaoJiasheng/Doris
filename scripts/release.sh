#!/usr/bin/env bash
# Build a signed + notarized + stapled DMG of Doris for direct
# distribution. Run from the repo root, expects:
#   - DORIS_TEAM_ID env var set to the Apple Developer team identifier
#     (e.g. ABCDEF1234); also referenced by project.yml + ExportOptions.plist
#   - Developer ID Application certificate installed in the login keychain
#   - `xcrun notarytool store-credentials doris-notary ...` already run once
#     so the credentials live in the keychain under that profile name
#   - `brew install create-dmg` already run
#
# Outputs:
#   build/release-<version>/Doris-<version>.dmg  (the file you ship)
#   build/release-<version>/Doris.xcarchive      (kept for crash symbolication)
#
# See docs/release.md for the one-time setup walkthrough.

set -euo pipefail
cd "$(dirname "$0")/.."

# ---------- preflight ----------

: "${DORIS_TEAM_ID:?DORIS_TEAM_ID env var not set, see docs/release.md}"

# App Store Connect API key — used by xcodebuild for automatic
# provisioning-profile fetching. Without these the build session
# can't authenticate with developer.apple.com from the CLI (newer
# macOS sandboxes Xcode's account state so it's invisible to
# xcodebuild). Set DORIS_ASC_KEY_PATH / ID / ISSUER via env or
# fall back to the standard location below; the .p8 is what you
# download once from appstoreconnect.apple.com (Team Keys).
ASC_KEY_PATH="${DORIS_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8}"
ASC_KEY_ID="${DORIS_ASC_KEY_ID:-AMDBKB83K9}"
ASC_ISSUER_ID="${DORIS_ASC_ISSUER_ID:-3659a31c-d035-4195-842f-d269268a59c3}"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "❌ App Store Connect API key missing at $ASC_KEY_PATH" >&2
  echo "   Generate one at https://appstoreconnect.apple.com/access/integrations/api" >&2
  echo "   and drop the .p8 into ~/.appstoreconnect/private_keys/" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "❌ create-dmg not installed. Run: brew install create-dmg" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning 2>/dev/null \
     | grep -q "Developer ID Application: .* ($DORIS_TEAM_ID)"; then
  echo "❌ No 'Developer ID Application' cert found for team $DORIS_TEAM_ID." >&2
  echo "   In Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile doris-notary --keychain "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  echo "❌ notarytool keychain profile 'doris-notary' missing. Run:" >&2
  echo "   xcrun notarytool store-credentials doris-notary \\" >&2
  echo "     --apple-id <your-apple-id> --team-id $DORIS_TEAM_ID --password <app-specific-pw>" >&2
  exit 1
fi

# ---------- version ----------

# Read MARKETING_VERSION from project.yml (single source of truth — the
# generated Info.plist uses the same value via XcodeGen interpolation).
VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml \
           | head -1 | awk -F'"' '{print $2}')"
: "${VERSION:?Could not parse MARKETING_VERSION from project.yml}"

BUILD_DIR="build/release-$VERSION"
ARCHIVE="$BUILD_DIR/Doris.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Doris.app"
DMG="$BUILD_DIR/Doris-$VERSION.dmg"

echo "📦 Building Doris v$VERSION → $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Strip macOS extended attributes from the source tree + any leftover
# DerivedData artifacts. macOS Sonoma+ stamps every file with
# `com.apple.provenance`, and downloaded assets often carry
# `com.apple.quarantine`; codesign on hardened-runtime apps rejects
# both with "resource fork, Finder information, or similar detritus
# not allowed". Cheap to clear, fatal if not.
echo "🧹 Stripping xattrs from source tree + DerivedData..."
xattr -cr "$PWD" 2>/dev/null || true
xattr -cr ~/Library/Developer/Xcode/DerivedData/Doris-* 2>/dev/null || true

# ---------- 1. archive ----------

echo "🔨 [1/6] Archiving (xcodebuild)..."
# Notes on the flags:
#   -destination "generic/platform=macOS" — disambiguates between
#     the multiple Mac targets that the scheme can resolve to (host
#     arch arm64, x86_64, "Any Mac"). Without this xcodebuild warns
#     and may pick a host-only build that fails archive.
#   -allowProvisioningUpdates — lets Xcode fetch / create the
#     provisioning profiles for each target's bundle id on the fly.
#     With Developer ID Application installed in keychain and the
#     team set, this auto-creates the needed profiles in Apple's
#     portal the first time a bundle id is encountered.
xcodebuild \
  -project Doris.xcodeproj \
  -scheme Doris-macOS \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$DORIS_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive 2>&1 | tail -25

[ -d "$ARCHIVE" ] || { echo "❌ archive failed; rerun for full xcodebuild output"; exit 1; }

# ---------- 2. export ----------

# Plist files don't do shell-variable interpolation when passed to
# xcodebuild — `$(DORIS_TEAM_ID)` survives literally and the export
# fails with "No Account for Team $(DORIS_TEAM_ID)". Generate the
# effective ExportOptions.plist with the real value substituted in.
EXPORT_PLIST="$BUILD_DIR/ExportOptions.effective.plist"
sed "s|\$(DORIS_TEAM_ID)|$DORIS_TEAM_ID|g" scripts/ExportOptions.plist > "$EXPORT_PLIST"

echo "📤 [2/6] Exporting signed .app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$DORIS_TEAM_ID" \
  2>&1 | tail -15

[ -d "$APP" ] || { echo "❌ export failed; no .app at $APP"; exit 1; }

# ---------- 3. preflight checks ----------

echo "🔍 [3/6] Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

# The embedded `doris` CLI must also be Developer ID signed + hardened-
# runtime — both are required for notarization. Catches any regression
# in the CLI target's settings before we burn a notary submission.
CLI="$APP/Contents/Resources/doris"
[ -x "$CLI" ] || { echo "❌ bundled CLI missing at $CLI"; exit 1; }
# Capture codesign's output once, then grep the variable — do NOT pipe
# `codesign -dvv` straight into `grep -q`. `grep -q` closes the pipe on
# its first match, `codesign` then takes SIGPIPE (exit 141), and with
# `set -o pipefail` the whole pipeline reports failure even though the
# pattern matched. That's a load-dependent flake that spuriously failed
# the "embedded CLI not Developer ID signed" check mid-release.
CLI_SIG="$(codesign -dvv "$CLI" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$CLI_SIG" \
  || { echo "❌ embedded CLI not Developer ID signed"; exit 1; }
grep -q "flags=.*runtime" <<<"$CLI_SIG" \
  || { echo "❌ embedded CLI missing hardened-runtime flag"; exit 1; }
echo "   ✓ CLI signed + hardened"

# spctl reports "unsigned" before notarization; that's expected here.
# We only use it post-staple to confirm Gatekeeper sees the ticket.

# ---------- 4. notarize ----------

echo "🍎 [4/6] Submitting to notary service (5-15 min)..."
ZIP="$BUILD_DIR/Doris.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --keychain-profile doris-notary --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --wait \
  --output-format normal
rm -f "$ZIP"

# ---------- 5. staple .app + build DMG + notarize DMG ----------

echo "🎟  [5/6] Stapling .app + building DMG..."
xcrun stapler staple "$APP"

# Stage the DMG payload: the .app plus a printed copy of the CLI
# manual so users get an offline reference alongside the installer.
# Pandoc renders the markdown to a self-contained PDF with the
# system-default LaTeX engine (xelatex), which handles the Chinese
# headings fine.
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
echo "📄 Rendering CLI manual to PDF..."
# Two-step pipeline that avoids needing MacTeX (~4GB) for the PDF
# engine: pandoc renders the markdown to a self-contained HTML with
# an inline stylesheet, then Google Chrome's headless mode prints it
# to PDF. Chrome is by far the most common HTML→PDF renderer present
# on dev macs, and its print engine handles CJK + code fences cleanly.
TMP_HTML="$BUILD_DIR/cli-manual.html"
pandoc docs/cli-manual.md \
  --standalone \
  --metadata title="Doris CLI Manual" \
  --to html5 \
  --css=scripts/cli-manual-print.css \
  --embed-resources \
  -o "$TMP_HTML" 2>&1 | tail -3

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "❌ Google Chrome not found at $CHROME — needed for PDF generation." >&2
  echo "   Either install Chrome, or swap to Safari/Chromium and update this script." >&2
  exit 1
fi
"$CHROME" \
  --headless=new \
  --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf="$DMG_STAGING/CLI Manual.pdf" \
  "file://$PWD/$TMP_HTML" 2>&1 | tail -2
[ -s "$DMG_STAGING/CLI Manual.pdf" ] \
  || { echo "❌ PDF generation produced an empty file"; exit 1; }
echo "   ✓ PDF: $DMG_STAGING/CLI Manual.pdf ($(du -h "$DMG_STAGING/CLI Manual.pdf" | cut -f1))"

# Background blank PNG keeps create-dmg from grumbling about a missing
# background; users see a clean install layout (just app → /Applications,
# plus the PDF for reference).
# `|| true`: create-dmg intermittently fails its FINAL step — unmounting
# the staging volume — with "hdiutil: couldn't unmount … resource busy"
# when Spotlight/Finder grabs the freshly-mounted volume before it can
# detach + convert. Don't let that abort the release (set -e); recover
# below instead.
create-dmg \
  --volname "Doris $VERSION" \
  --window-size 600 400 \
  --icon-size 96 \
  --icon "Doris.app" 140 180 \
  --icon "CLI Manual.pdf" 300 180 \
  --app-drop-link 460 180 \
  --no-internet-enable \
  "$DMG" \
  "$DMG_STAGING" 2>&1 | tail -5 || true

# Recovery: when the unmount flake hits, the layout AppleScript has
# already run, so create-dmg leaves a fully-populated read-write image
# (rw.<pid>.Doris-<version>.dmg) — possibly still attached. Force-detach
# any volume backed by it, then convert it to the final compressed DMG
# ourselves. This preserves the icon layout that was already applied.
if [ ! -f "$DMG" ]; then
  echo "⚠️  create-dmg didn't finalize the DMG (busy-volume unmount). Recovering from the rw image..."
  hdiutil info 2>/dev/null \
    | awk '/^image-path/{p=($0 ~ /rw\..*Doris-/)} /\/dev\/disk[0-9]+\t/{if(p) print $1}' \
    | while read -r dev; do hdiutil detach -force "$dev" 2>/dev/null || true; done
  RW="$(ls -t "$BUILD_DIR"/rw.*.dmg 2>/dev/null | head -1)"
  [ -n "$RW" ] || { echo "❌ DMG build failed and no rw image to recover from"; exit 1; }
  hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" 2>&1 | tail -3
  rm -f "$RW"
fi
[ -f "$DMG" ] || { echo "❌ DMG not produced at $DMG"; exit 1; }

# Notarize the DMG itself too — without this, downloading the DMG and
# offline-launching it on a fresh Mac still triggers a Gatekeeper
# "verifying" spinner the first time the user mounts it. With both .app
# and .dmg notarized + stapled, the user gets the silent open path.
echo "🍎 Submitting DMG to notary service..."
xcrun notarytool submit "$DMG" \
  --keychain-profile doris-notary --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --wait \
  --output-format normal
xcrun stapler staple "$DMG"

# ---------- 6. final validation ----------

echo "✅ [6/6] Validating ticket + Gatekeeper assessment..."
xcrun stapler validate "$DMG" 2>&1 | tail -2
spctl --assess --type install --verbose "$DMG" 2>&1 | tail -2 \
  || true # spctl is informational at this point

SIZE="$(du -h "$DMG" | cut -f1)"
echo ""
echo "✨ Release built: $DMG ($SIZE)"
echo ""
echo "Next:"
echo "  - Test by copy-pasting the DMG to another Mac account and double-clicking."
echo "  - First production-signed launch may take ~10s while CloudKit zones bootstrap."
