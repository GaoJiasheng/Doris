# doris CloudKit schema

All records live in the **private database** of `iCloud.com.gavin.doris`.

## Custom zones

| Zone           | Contents                                                    | Managed by |
| -------------- | ----------------------------------------------------------- | ---------- |
| `NotesZone`    | Folder, Note, ChecklistItem, Tag (synced via SwiftData)     | SwiftData mirror |
| `MessagesZone` | Message + message-scoped Attachment (synced via SwiftData)  | SwiftData mirror |
| `OutboxZone`   | `CK_OutboxItem` records (raw CloudKit)                      | `OutboxPublisher` |
| `DevicesZone`  | `CK_Device` records (raw CloudKit)                          | `DeviceRegistry` |

`SwiftData mirror` zones are populated automatically by SwiftData's
`NSPersistentCloudKitContainer` — see "Notes/Messages via SwiftData"
below. The `OutboxZone` + `DevicesZone` use raw `CKModifyRecordsOperation`
because they need immediate-fire silent-push delivery to other
devices, which SwiftData's batched mirror doesn't guarantee.

Bootstrap (zone creation + subscription) runs on first launch in
`CloudKitBootstrap.ensureZonesAndSubscriptions()`.

## `CK_OutboxItem`

```
recordType: CK_OutboxItem
recordName: outbox-<originalMessageID>

fields:
  payloadJSON       : Bytes      // IPCNotifyPayload, JSON, sortedKeys, ISO8601
  originDeviceID    : String     // UUID string
  originalMessageID : String     // UUID string
  createdAt         : Date
```

A `CKQuerySubscription` (subscription id `doris-outbox-sub-v1`) on
this record type with `firesOnRecordCreation` and
`shouldSendContentAvailable = true` produces the silent-push delivery
on receivers.

## `CK_Device`

```
recordType: CK_Device
recordName: device-<deviceUUID>

fields:
  name         : String
  platform     : String   // macOS | iOS | iPadOS
  lastSeenAt   : Date
```

Each device upserts its own record on launch; the Devices tab in the
app reads from this zone.

## Notes/Messages via SwiftData

SwiftData with
`ModelConfiguration(cloudKitDatabase: .private("iCloud.com.gavin.doris"))`
mirrors the `@Model` types into the matching custom zone automatically.
The CloudKit dashboard shows them under `CD_<ClassName>` record types.

`@Model` types as of 1.0.0:

| SwiftData type | CloudKit record type | Zone |
|---|---|---|
| `Note`          | `CD_Note`          | `NotesZone` |
| `Folder`        | `CD_Folder`        | `NotesZone` |
| `ChecklistItem` | `CD_ChecklistItem` | `NotesZone` |
| `Tag`           | `CD_Tag`           | `NotesZone` |
| `Attachment`    | `CD_Attachment`    | `NotesZone` |
| `Message`       | `CD_Message`       | `MessagesZone` |
| `Device`        | `CD_Device`        | `MessagesZone` |
| `UserSettings`  | `CD_UserSettings`  | `MessagesZone` |

`Note`'s 1.0.0 field set: `id`, `title`, `bodyMarkdown`,
`isChecklist`, `pinned`, `archived`, `done`, `completedAt`,
`archivedAt`, `deleted`, `deletedAt`, `order`, `colorHex`, `dueDate`,
`createdAt`, `updatedAt`, `folder` (relationship), `tags`
(relationship), `promotedFrom` (relationship to `Message`),
`checklistItems` (legacy relationship — not written by current editor;
markdown-body `- [x]` lines are the source of truth via
`Note.checklistProgress`).

`Attachment` gained three fields in 1.9.0, for images placed in a note's
body: `data` (bytes, `@Attribute(.externalStorage)` — CloudKit keeps it
as an asset, `CD_data_ckAsset`, or inline as `CD_data` when small),
`pixelWidth` and `pixelHeight` (`Int`, 0 for attachments that aren't body
images). The body refers to an image by its attachment id, one per line:
`![](doris-image:<UUID>?w=s|m|l|f)` — see `NoteImageMarkup`.

## Cleanup

- The originating device sweeps `CK_OutboxItem` records older than 24
  hours via a periodic `CKQueryOperation`. Receivers do not delete;
  they only consume.
- `SyncTimer.purgeTombstones` (runs on every 60 s poke) hard-deletes
  notes with `deleted && updatedAt < 24h ago` — the trash. Deleting via
  a soft-delete that is purged later is the fix for the CloudKit
  hard-delete race that bit us pre-1.0. Archived notes are kept
  indefinitely; through 1.8.3 they were also purged, 30 days after
  their last edit. See `SyncTimer.swift`.
- `NoteImageStore.purgeOrphans` (hourly, from `SyncTimer`) deletes body
  images no note references any more, a week after they were added —
  the grace covers undo, and a body edit that syncs after its image.
  A purged note's images that another note still shows (copied across)
  are detached first instead of cascading away with it.

## Development vs Production environments

CloudKit splits records into two completely independent databases per
container:

- **Development env** — apps signed with the "Apple Development"
  certificate hit this. Default for Debug Xcode builds.
- **Production env** — apps signed with "Apple Distribution" (App
  Store / TestFlight) or "Developer ID Application" (DMG) hit this.

The two databases share schema but **not data**. A Debug build run
locally on Mac and a TestFlight build on iOS therefore do NOT see each
other's records — same Apple ID, same container, but a hard split.

For 1.0.0 we ship:
- **Mac DMG** signed with Developer ID Application → Production env
- **iOS TestFlight** signed with Apple Distribution → Production env

Both binaries hit the same Production database, so data syncs between
them.

### Schema deployment

Schema in the Development env auto-creates on first `@Model` write.
Schema in Production must be **explicitly deployed** via
<https://icloud.developer.apple.com/dashboard> → container → Schema →
**Deploy Schema Changes to Production**. Without this, Production
record-create operations fail with "Unknown record type" and the
SwiftData mirror swallows the error (silent — only visible in the
ANSCKEVENT table inside the local SwiftData store).

Deploy any time you add a `@Model` type or a property. Doing it from
the dashboard takes ~10 seconds.

Every build is pinned to Production (`icloud-container-environment` in
the entitlements), so nothing creates new fields in Development on its
own any more. Push them there first, from a Debug build re-signed for
Development:

```bash
xcodebuild -project Doris.xcodeproj -scheme Doris-macOS -configuration Debug \
  -destination "generic/platform=macOS" -derivedDataPath /tmp/dd-schema \
  -allowProvisioningUpdates build
APP=/tmp/dd-schema/Build/Products/Debug/Doris.app
codesign -d --entitlements :- "$APP" > /tmp/ent.plist
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.icloud-container-environment Development" /tmp/ent.plist
codesign --force --sign "Apple Development" --entitlements /tmp/ent.plist \
  --options runtime --preserve-metadata=identifier,flags "$APP"
"$APP/Contents/MacOS/Doris" --init-cloudkit-schema
```

`--init-cloudkit-schema` (Debug builds only, `CloudKitSchemaInitializer`)
runs `initializeCloudKitSchema` on a throwaway store and exits before the
app starts; it refuses to run unless the signature says Development.
Then deploy from the dashboard as above — **before** releasing a build
that writes the new fields.
