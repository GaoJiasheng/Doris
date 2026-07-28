#!/usr/bin/env bash
# Build + upload the iOS app to App Store Connect. Once the upload
# lands and Apple's "Processing" phase finishes (5-15 min), the build
# is available in TestFlight Internal Testing — install via the
# TestFlight app on your iPhone. Submitting for full App Store
# review needs metadata / screenshots / privacy questionnaire filled
# in via the ASC dashboard.
#
# Prerequisites mirror release.sh (Mac):
#   - DORIS_TEAM_ID env exported
#   - Apple Development + iOS Distribution / Apple Distribution certs
#     in login keychain (the latter is auto-created by Xcode on first
#     archive when the API key has App Manager+ scope)
#   - App Store Connect API key under
#     ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#   - The iOS app's bundle id `com.gavin.doris.ios` registered at
#     developer.apple.com with iCloud (CloudKit), Push Notifications,
#     and App Groups capabilities. App ID for share / widget /
#     intents extensions registered too.
#
# Outputs:
#   build/release-<version>-ios/Doris.ipa   (uploaded to ASC)
#   build/release-<version>-ios/Doris.xcarchive (kept for crash symbolication)

set -euo pipefail
cd "$(dirname "$0")/.."

# ---------- preflight ----------

: "${DORIS_TEAM_ID:?DORIS_TEAM_ID env var not set, see docs/release.md}"

ASC_KEY_PATH="${DORIS_ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8}"
ASC_KEY_ID="${DORIS_ASC_KEY_ID:-AMDBKB83K9}"
ASC_ISSUER_ID="${DORIS_ASC_ISSUER_ID:-3659a31c-d035-4195-842f-d269268a59c3}"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "❌ App Store Connect API key missing at $ASC_KEY_PATH" >&2
  exit 1
fi

# ---------- version ----------

VERSION="$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml \
           | sed -n '2p' | awk -F'"' '{print $2}')"
# iOS scheme uses a separate MARKETING_VERSION in project.yml (Doris-iOS
# target's settings block — the sed -n '2p' picks the second match,
# which is iOS's). Fall back to 0.2.0 if parsing misses.
: "${VERSION:=0.2.0}"

BUILD_DIR="build/release-${VERSION}-ios"
ARCHIVE="$BUILD_DIR/Doris.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
IPA="$EXPORT_DIR/Doris.ipa"

echo "📦 Building Doris iOS v$VERSION → $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Strip extended attributes (same reason as macOS path).
echo "🧹 Stripping xattrs from source tree + DerivedData..."
xattr -cr "$PWD" 2>/dev/null || true
xattr -cr ~/Library/Developer/Xcode/DerivedData/Doris-* 2>/dev/null || true

# ---------- 1. archive ----------

echo "🔨 [1/4] Archiving (xcodebuild)..."
xcodebuild \
  -project Doris.xcodeproj \
  -scheme Doris-iOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$DORIS_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive 2>&1 | tail -25

[ -d "$ARCHIVE" ] || { echo "❌ archive failed"; exit 1; }

# ---------- 2. export IPA ----------

EXPORT_PLIST="$BUILD_DIR/ExportOptions-iOS.effective.plist"
sed "s|\$(DORIS_TEAM_ID)|$DORIS_TEAM_ID|g" scripts/ExportOptions-iOS.plist > "$EXPORT_PLIST"

echo "📤 [2/4] Exporting signed IPA..."
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

[ -f "$IPA" ] || { echo "❌ IPA export failed — looked for $IPA"; exit 1; }
echo "   ✓ IPA: $IPA ($(du -h "$IPA" | cut -f1))"

# ---------- entitlement guard ----------
#
# Xcode's automatic signing DROPS entitlements the App ID doesn't have
# enabled, without warning and without failing the build. That is how a
# release once shipped with `aps-environment` missing: the source
# .entitlements asked for it, the App ID didn't grant it, the log said
# nothing, and inbound CloudKit sync was dead on arrival because the mirror
# never received its subscription pushes.
#
# So verify against the SIGNED artifact rather than trusting the inputs.
ENT_TMP="$(mktemp -d)"
unzip -q -o "$IPA" -d "$ENT_TMP" 'Payload/Doris.app/*' 2>/dev/null || true
SIGNED_ENT="$(codesign -d --entitlements :- "$ENT_TMP/Payload/Doris.app" 2>/dev/null)"
MISSING=""
# `aps-environment` is the iOS spelling — macOS uses
# `com.apple.developer.aps-environment`, and checking for the macOS key here
# is how the first version of this guard reported the right failure for the
# wrong reason. Match the exact key so a renamed/misspelled entitlement can't
# pass by matching some other line.
for key in \
  "aps-environment" \
  "com.apple.developer.icloud-services" \
  "com.apple.security.application-groups"
do
  if ! printf '%s' "$SIGNED_ENT" | grep -q "<key>$key</key>"; then
    MISSING="$MISSING $key"
  fi
done
rm -rf "$ENT_TMP"
if [ -n "$MISSING" ]; then
  echo "❌ The signed app is MISSING entitlements:$MISSING" >&2
  echo "   Xcode strips entitlements the App ID doesn't grant, silently." >&2
  echo "   Enable the matching capability for com.gavin.doris.ios at" >&2
  echo "   developer.apple.com → Identifiers, then re-run (the profile" >&2
  echo "   regenerates automatically). Refusing to ship a build whose" >&2
  echo "   iCloud sync would be broken." >&2
  exit 1
fi
echo "   ✓ entitlements present in signed app (push + iCloud + app group)"

# ---------- 3. validate ----------

echo "🔍 [3/4] Validating with App Store Connect..."
xcrun altool --validate-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -10

# ---------- 4. upload ----------

echo "🚀 [4/4] Uploading to App Store Connect (5-15 min processing after)..."
xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -15

SIZE="$(du -h "$IPA" | cut -f1)"
echo ""
echo "✨ Upload complete: $IPA ($SIZE)"
echo ""
echo "Next:"
echo "  - Wait 5-15 min for Apple to process the build."
echo "  - Open https://appstoreconnect.apple.com → TestFlight → builds list."
echo "  - Add yourself as Internal Tester (Users and Access → Apple Account)."
echo "  - Install TestFlight on your iPhone, sign in, accept the invite,"
echo "    tap Install on the Doris build."
echo "  - To submit for full App Store review, finish the metadata /"
echo "    screenshots / privacy questionnaire on the ASC dashboard,"
echo "    then click \"Add for Review\"."
