# Releasing Doris

1.0.0 ships **two binaries from one repo**:

| Target | Channel | Pipeline |
|---|---|---|
| **Mac** | Direct distribution DMG (Developer ID) | `scripts/release.sh` (aspirational) **OR** manual codesign + hdiutil (what 1.0.0 actually shipped) |
| **iOS** | TestFlight → App Store | `scripts/release-ios.sh` |

The Mac story has a wrinkle worth reading before your first release —
see [Mac DMG: which path do I use?](#mac-dmg-which-path-do-i-use).

---

## One-time setup

### 1. Apple Developer Program enrollment

Already done if you can sign into <https://developer.apple.com/account>
and see a Team ID under "Membership details."

### 2. Install signing certificates

You need both in your **login keychain**:

- **Apple Development** — for Debug / archive identity
- **Developer ID Application** — for Mac DMG distribution
- **Apple Distribution** — for iOS TestFlight / App Store

Xcode → Settings → Accounts → your Apple ID → Manage Certificates →
`+` for each. Verify:

```bash
security find-identity -v -p codesigning
# Should list at least three rows, one per cert type
```

### 3. App Store Connect API key (.p8)

Used by `release-ios.sh` for `altool` and by `release.sh` for
`xcodebuild -allowProvisioningUpdates`.

1. Go to <https://appstoreconnect.apple.com/access/api>
2. Generate a new key. **Role = Admin** is what 1.0.0 was tested
   with. App Manager may also work; lower roles will fail with
   "Developer ID profile auto-create denied" during Mac archive.
3. Download the `.p8` (you can only download it once).
4. Drop into:
   ```
   ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
   ```
5. Note the Key ID and Issuer ID from the dashboard.

The release scripts default to the key shipped with this repo's
README — override via env vars if yours differs:
```bash
export DORIS_ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXX.p8
export DORIS_ASC_KEY_ID=XXX
export DORIS_ASC_ISSUER_ID=xxx-xxx-xxx-xxx
```

### 4. notarization keychain profile (for the Mac notarized path)

Only needed if you intend to run the full `scripts/release.sh`
(notarized DMG path). Skip if you'll use the manual codesign path
[described below](#mac-dmg-which-path-do-i-use).

```bash
xcrun notarytool store-credentials doris-notary \
  --apple-id   <your-apple-id-email> \
  --team-id    D33974QQTD \
  --password   <app-specific-password from appleid.apple.com>
```

### 5. Tools

```bash
brew install create-dmg pandoc xcodegen gh
brew install --cask google-chrome   # used by release.sh for CLI Manual PDF
```

### 6. Register Bundle IDs + iCloud Container in the Developer Portal

In <https://developer.apple.com/account/resources/identifiers/list>:

| Type | Identifier | Capabilities |
|---|---|---|
| App ID | `com.gavin.doris` | iCloud (CloudKit), Push Notifications, App Groups |
| App ID | `com.gavin.doris.share-mac` | App Groups |
| App ID | `com.gavin.doris.widget-mac` | iCloud (CloudKit), App Groups |
| App ID | `com.gavin.doris.intents-mac` | App Groups |
| App ID | `com.gavin.doris.doris-cli` | App Groups |
| App ID | `com.gavin.doris.ios` | iCloud (CloudKit), Push Notifications, App Groups |
| iCloud Container | `iCloud.com.gavin.doris` | (n/a) |
| App Group | `group.com.gavin.doris.shared` | (n/a) |

### 7. Deploy CloudKit schema to Production (once per schema change)

After your first Apple-Development-signed Debug build creates record
types in Development env:

1. Open <https://icloud.developer.apple.com/dashboard>
2. Container → Schema → **Deploy Schema Changes to Production**
3. Confirm

Without this, the shipped (Production-env) build can't read/write —
SwiftData CloudKit mirror records errors in ANSCKEVENT table but
swallows them at the API layer. See `docs/cloudkit-schema.md` for the
Dev/Prod environment split.

### 8. Environment

```bash
# Add to ~/.zshrc
export DORIS_TEAM_ID=D33974QQTD
```

---

## iOS — TestFlight

Once setup is done, every iOS release is one command:

```bash
scripts/release-ios.sh
```

Reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from
`project.yml` (the second target's settings block — the iOS one).
**Bump the build number before each upload** — Apple rejects
identical (version, build) tuples.

The script will:

1. Archive `Doris-iOS` (Release config, Apple Distribution cert) via
   `xcodebuild ... -authenticationKeyPath/-ID/-IssuerID`
2. Export an IPA via the ASC API key auth (`-exportArchive`)
3. Validate with `altool --validate-app`
4. Upload with `altool --upload-app`
5. Apple processes 5-15 minutes after upload; the build then shows in
   TestFlight Internal Testing

Output: `build/release-<version>-ios/Doris.ipa`.

### Recurring iOS gotchas

| Symptom | Fix |
|---|---|
| Build hidden from TestFlight after processing — "Missing Compliance" | `ITSAppUsesNonExemptEncryption: false` already set in `project.yml`. New builds auto-comply. For an old uploaded build, patch via API: PATCH `/v1/builds/{id}` with `usesNonExemptEncryption: false` |
| ASC error 90717 (icon alpha channel) | Round-trip `icon_1024.png` through `sips -s format jpeg ... && sips -s format png ...` to strip alpha. Already applied to the repo asset |
| ASC error 90474 (iPad orientations) | `UIRequiresFullScreen: true` set in `project.yml` |
| altool upload network errors mid-multipart | altool retries individual parts automatically; only abort if the final `UPLOAD SUCCEEDED` line never prints |

---

## Mac DMG: which path do I use?

### Path A: `scripts/release.sh` — full notarized pipeline (aspirational)

This is the "right" way. Archive → export → notarize → DMG → notarize
DMG → staple. Result: a DMG that mounts silently on any Mac without
right-click-Open dance.

```bash
scripts/release.sh
```

**Status as of 1.0.0**: doesn't work end-to-end. Two failure modes:

1. `xcodebuild -exportArchive` with `signingStyle: automatic` fails
   because the ASC API key's role can't auto-create a Developer ID
   profile carrying all the capability entitlements (App Groups,
   iCloud, Push). Apple gates this behind the App Manager+ scope.
2. Even when the export path works, `xcrun notarytool submit --wait`
   has been observed to hang "In Progress" indefinitely (Apple-side
   issue, no client signal). Hours, sometimes 18+.

If your ASC API key role gets bumped to App Manager+ and Apple's
notary service is responsive that day, this path works clean.

### Path B: manual codesign + hdiutil DMG (what 1.0.0 actually shipped)

Bypasses `exportArchive` and the notary entirely. Re-signs the
archive's `.app` locally using the Direct provisioning profile
already in your Xcode profiles folder, then bundles it into a DMG
via `hdiutil`/`create-dmg`. The DMG is **not notarized**, so first
launch on another Mac needs right-click → Open to bypass Gatekeeper
(one time per install).

The recipe is captured in the conversation that produced 1.0.0; the
key steps:

```bash
# 1. Archive (same as path A)
xcodebuild \
  -project Doris.xcodeproj \
  -scheme Doris-macOS \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "build/release-$VERSION/Doris.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8" \
  -authenticationKeyID "AMDBKB83K9" \
  -authenticationKeyIssuerID "<issuer>" \
  DEVELOPMENT_TEAM="D33974QQTD" \
  CODE_SIGN_STYLE=Automatic \
  archive

# 2. Copy app out, swap embedded provisioning profile to the Direct one
ARCHIVE_APP="build/release-$VERSION/Doris.xcarchive/Products/Applications/Doris.app"
STAGE="build/release-$VERSION-unnotarized"
APP="$STAGE/Doris.app"
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<direct-profile-uuid>.provisionprofile"
mkdir -p "$STAGE"
cp -R "$ARCHIVE_APP" "$APP"
xattr -cr "$APP"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# 3. Build a production-env entitlements plist (sandbox flags from
#    archive + aps-environment=production + icloud-container-environment=Production)
cat > "$STAGE/app.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>com.apple.application-identifier</key>
    <string>D33974QQTD.com.gavin.doris</string>
    <key>com.apple.developer.team-identifier</key>
    <string>D33974QQTD</string>
    <key>com.apple.developer.aps-environment</key>
    <string>production</string>
    <key>com.apple.developer.icloud-container-environment</key>
    <string>Production</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array><string>iCloud.com.gavin.doris</string></array>
    <key>com.apple.developer.icloud-services</key>
    <array><string>CloudKit</string></array>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.application-groups</key>
    <array><string>group.com.gavin.doris.shared</string></array>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.network.client</key><true/>
    <key>keychain-access-groups</key>
    <array><string>D33974QQTD.group.com.gavin.doris.shared</string></array>
</dict>
</plist>
PLIST

# 4. Re-sign CLI first (inner-first signing order), then main app
codesign -d --entitlements :- "$APP/Contents/Resources/doris" > "$STAGE/cli.entitlements"
IDENTITY="Developer ID Application: <Your Name> (D33974QQTD)"
codesign --force --sign "$IDENTITY" --options=runtime --timestamp \
  --entitlements "$STAGE/cli.entitlements" "$APP/Contents/Resources/doris"
codesign --force --sign "$IDENTITY" --options=runtime --timestamp \
  --entitlements "$STAGE/app.entitlements" "$APP"

# 5. Verify
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP"   # expect: Authority=Developer ID Application... + Timestamp= + flags=...runtime

# 6. Bundle into a DMG with create-dmg (volume icon + CLI manual PDF)
# … see commits in git history for the full create-dmg invocation
```

The full path is currently inlined in chat history rather than scripted
— if you find yourself running it more than 2-3 times, lift it into
`scripts/release-mac-unnotarized.sh`.

### Output

Both paths land at:
```
build/release-<version>-unnotarized/Doris-<version>.dmg     (path B)
build/release-<version>/Doris-<version>.dmg                  (path A, when it works)
```

## Versioning

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
are the single source of truth — bump both before running a release.
Two targets, two version blocks (Mac then iOS):

```bash
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" project.yml
# 109:        MARKETING_VERSION: "1.0.0"     # Mac
# 110:        CURRENT_PROJECT_VERSION: "1"
# 274:        MARKETING_VERSION: "1.0.0"     # iOS
# 275:        CURRENT_PROJECT_VERSION: "1"
```

After bumping, regenerate the Xcode project:

```bash
scripts/generate-project.sh
```

Mac and iOS keep separate build counters. iOS must bump build per
upload (TestFlight de-dupes by (version, build)). Mac can stay at
build 1 for a marketing version unless you want to ship multiple DMGs
of the same version.

## Tagging a release

```bash
git tag -a v1.0.0 <commit> -m "Doris 1.0.0 — <one-line summary>"
git push origin v1.0.0
```

GitHub auto-creates a Release entry from the tag; attach the DMG by
editing the release.

## Troubleshooting

### "No Developer ID Application cert found"

Step 2. Re-run `security find-identity -v -p codesigning` to confirm.
If still empty, the cert may have been revoked or is in a different
keychain — try Xcode → Settings → Accounts → Download Manual Profiles.

### Notary submission "In Progress" forever

Known Apple-side flakiness. If it doesn't resolve in 1 h, kill the
script and switch to path B (manual codesign).

### "exportArchive requires a provisioning profile with the App Groups, iCloud, and Push Notifications features"

Path A only. ASC API key role insufficient to auto-create. Either:
- Bump the API key role to App Manager+ in ASC and retry, OR
- Switch to path B

### Old TestFlight builds stuck at "Missing Compliance"

The plist key didn't exist on those builds. Patch via API:
```bash
JWT=...   # ES256-signed
curl -X PATCH -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"data":{"type":"builds","id":"<build-id>","attributes":{"usesNonExemptEncryption":false}}}' \
  "https://api.appstoreconnect.apple.com/v1/builds/<build-id>"
```

### First-launch CloudKit failures on the shipped build

Confirm step 7 (schema deploy to Production). The shipped build's
logs say "CloudKit Production schema not yet deployed" or
records-create errors show up in the ANSCKEVENT table inside the
local SwiftData store.

### Mac dev build + iOS TestFlight don't sync

They're on different CloudKit envs. Apple Development cert (Mac
Debug) → Development env; Apple Distribution / Developer ID (iOS
TestFlight / Mac DMG) → Production env. For cross-device sync to
work, both binaries need to be Production-signed — see
`docs/cloudkit-schema.md` "Development vs Production environments."

### CI / GitHub Actions

Not wired up yet. If you wire it, the keychain-profile pattern for
notarization doesn't translate to CI cleanly — pass the app-specific
password as a secret env var to a fresh `notarytool store-credentials`
call inside the runner, then proceed with `notarytool submit
--keychain-profile`. ASC API key auth (the `.p8` file) translates
fine — drop into the runner's `~/.appstoreconnect/private_keys/`.
