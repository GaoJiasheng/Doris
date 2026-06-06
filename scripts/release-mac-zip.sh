#!/usr/bin/env bash
# Build a Developer-ID-signed + notarized + stapled .zip of Doris for
# direct distribution — the reliable "path B" recipe from docs/release.md
# (manual re-sign), packaged as a zip instead of a DMG.
#
# Why path B: `xcodebuild -exportArchive` with automatic signing can't
# auto-create a Developer ID profile carrying the App Groups / iCloud /
# Push entitlements unless the ASC key has App Manager+ scope. So we
# archive, then re-sign the archived .app locally with the Direct
# provisioning profile + production entitlements already proven in 1.0.0.
#
# Output: build/release-<version>/Doris-<version>.zip
#
# Prereqs (all already set up on this machine — see docs/release.md):
#   - DORIS_TEAM_ID                     (D33974QQTD)
#   - Developer ID Application cert in login keychain
#   - ASC API key at ~/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8
#   - notarytool keychain profile 'doris-notary'
#   - Direct provisioning profile installed (UUID below)

set -euo pipefail
cd "$(dirname "$0")/.."

# ---------- config ----------

DORIS_TEAM_ID="${DORIS_TEAM_ID:-D33974QQTD}"
ASC_KEY_PATH="${DORIS_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8}"
ASC_KEY_ID="${DORIS_ASC_KEY_ID:-AMDBKB83K9}"
ASC_ISSUER_ID="${DORIS_ASC_ISSUER_ID:-3659a31c-d035-4195-842f-d269268a59c3}"
IDENTITY="${DORIS_DEVID_IDENTITY:-Developer ID Application: Gavin Gao (D33974QQTD)}"
PROFILE_UUID="${DORIS_DIRECT_PROFILE_UUID:-dec15872-dd85-4a9a-b796-818fda8d5ab3}"
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$PROFILE_UUID.provisionprofile"
NOTARY_PROFILE="${DORIS_NOTARY_PROFILE:-doris-notary}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# ---------- preflight ----------

[ -f "$ASC_KEY_PATH" ] || { echo "❌ ASC key missing at $ASC_KEY_PATH"; exit 1; }
[ -f "$PROFILE" ]      || { echo "❌ Direct provisioning profile missing at $PROFILE"; exit 1; }
security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
  || { echo "❌ Developer ID identity not found: $IDENTITY"; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --keychain "$LOGIN_KEYCHAIN" >/dev/null 2>&1 \
  || { echo "❌ notary keychain profile '$NOTARY_PROFILE' missing"; exit 1; }

# ---------- version ----------

VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | awk -F'"' '{print $2}')"
: "${VERSION:?Could not parse MARKETING_VERSION from project.yml}"

BUILD_DIR="build/release-$VERSION"
ARCHIVE="$BUILD_DIR/Doris.xcarchive"
STAGE="$BUILD_DIR/zip-staging"
APP="$STAGE/Doris.app"
ZIP="$BUILD_DIR/Doris-$VERSION.zip"

echo "📦 Building Doris v$VERSION (Developer ID zip) → $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$STAGE"

echo "🧹 Stripping xattrs..."
xattr -cr "$PWD" 2>/dev/null || true
xattr -cr ~/Library/Developer/Xcode/DerivedData/Doris-* 2>/dev/null || true

# ---------- 1. archive ----------

echo "🔨 [1/6] Archiving (xcodebuild, ~5 min)..."
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
  archive 2>&1 | tail -12

ARCHIVE_APP="$ARCHIVE/Products/Applications/Doris.app"
[ -d "$ARCHIVE_APP" ] || { echo "❌ archive failed — no app at $ARCHIVE_APP"; exit 1; }

# ---------- 2. stage + swap profile ----------

echo "📂 [2/6] Staging app + swapping in the Direct provisioning profile..."
cp -R "$ARCHIVE_APP" "$APP"
xattr -cr "$APP"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# ---------- 3. entitlements ----------

echo "🔑 [3/6] Writing production entitlements..."
APP_ENT="$BUILD_DIR/app.entitlements"
cat > "$APP_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.application-identifier</key><string>D33974QQTD.com.gavin.doris</string>
    <key>com.apple.developer.team-identifier</key><string>D33974QQTD</string>
    <key>com.apple.developer.aps-environment</key><string>production</string>
    <key>com.apple.developer.icloud-container-environment</key><string>Production</string>
    <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.com.gavin.doris</string></array>
    <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.application-groups</key><array><string>group.com.gavin.doris.shared</string></array>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key><array><string>/.codex/</string><string>/.claude/</string></array>
    <key>com.apple.security.network.client</key><true/>
    <key>keychain-access-groups</key><array><string>D33974QQTD.group.com.gavin.doris.shared</string></array>
</dict></plist>
PLIST

# CLI keeps its own minimal entitlements (App Group only, no sandbox).
CLI="$APP/Contents/Resources/doris"
CLI_ENT="$BUILD_DIR/cli.entitlements"
codesign -d --entitlements :- "$CLI" > "$CLI_ENT" 2>/dev/null \
  || cat > "$CLI_ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.application-groups</key><array><string>group.com.gavin.doris.shared</string></array></dict></plist>
PLIST

# ---------- 4. re-sign (inner-first) ----------

echo "✍️  [4/6] Re-signing with Developer ID..."
# Any nested frameworks / dylibs / appex first (defensive — the mac app
# currently embeds none, but sign them if a future build does).
while IFS= read -r nested; do
  [ -n "$nested" ] || continue
  echo "    · nested: ${nested#$APP/}"
  codesign --force --sign "$IDENTITY" --options=runtime --timestamp "$nested"
done < <(find "$APP" \( -name "*.dylib" -o -name "*.framework" -o -name "*.appex" \) 2>/dev/null)

# Embedded CLI (inner), then the app (outer).
[ -x "$CLI" ] || { echo "❌ bundled CLI missing at $CLI"; exit 1; }
codesign --force --sign "$IDENTITY" --options=runtime --timestamp \
  --entitlements "$CLI_ENT" "$CLI"
codesign --force --sign "$IDENTITY" --options=runtime --timestamp \
  --entitlements "$APP_ENT" "$APP"

echo "🔍 Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3
# Capture codesign output to a variable BEFORE grepping. Piping
# `codesign -dvv | grep -q` under `set -o pipefail` is a trap: grep -q
# exits on first match and closes the pipe, so codesign (still printing
# its cert chain) dies with SIGPIPE and the pipeline reports failure
# even though the pattern matched.
CLI_SIG="$(codesign -dvv "$CLI" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$CLI_SIG" \
  || { echo "❌ CLI not Developer ID signed"; exit 1; }
grep -q "flags=.*runtime" <<<"$CLI_SIG" \
  || { echo "❌ CLI missing hardened-runtime flag"; exit 1; }
echo "   ✓ app + CLI Developer ID signed + hardened"

# ---------- 5. notarize ----------

echo "🍎 [5/6] Notarizing (5-15 min)..."
NOTARIZE_ZIP="$BUILD_DIR/Doris-notarize.zip"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" --keychain "$LOGIN_KEYCHAIN" \
  --wait --output-format normal 2>&1 | tee "$BUILD_DIR/notary.log"
grep -q "status: Accepted" "$BUILD_DIR/notary.log" \
  || { echo "❌ notarization not Accepted — see $BUILD_DIR/notary.log"; exit 1; }
rm -f "$NOTARIZE_ZIP"

# ---------- 6. staple + final zip ----------

echo "🎟  [6/6] Stapling + packaging final zip..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" 2>&1 | tail -1
# ditto --keepParent so the zip expands to "Doris.app", not loose contents.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP" 2>&1 | tail -2 || true

SIZE="$(du -h "$ZIP" | cut -f1)"
echo ""
echo "✨ Release built: $ZIP ($SIZE)"
echo "   Notarized + stapled — downloads open without the right-click dance."
