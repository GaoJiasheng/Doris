# doris architecture

Long-form companion to the v1-design notes. Summarizes how the pieces
fit together for someone reading the codebase fresh post-1.0.

## Module graph

```
                  ┌─────────────────────────────────────────────┐
                  │                   Doris-macOS                │
                  │  DorisApp · AppDelegate · Sidebar · Notch    │
                  │  IPC drainer · Anchor · Voice · Scenes       │
                  └────────────────┬────────────────────────────┘
                                   │
                  ┌────────────────┴────────────────┐
                  │           Doris-iOS              │
                  │  DorisApp · AppDelegate         │
                  │  Scenes (Today/Notes/Events/    │
                  │  Settings/CalendarTimeline)     │
                  └────────────────┬────────────────┘
                                   │
       ┌───────────────────────────┴──────────────┐
       │                                          │
┌──────▼──────────────┐  ┌────────────────┐   ┌──▼──────────────┐
│   DorisMacChrome    │  │    DorisUI     │   │   DorisCore     │
│  PanelMaker         │  │  Today / Notes │   │  Schema (@Model)│
│  AnchorPanel        │  │  Events / Cyber│   │  Sync (CK zones,│
│  HotSide adapter    │  │  Theme         │   │  OutboxPub,…)   │
└─────────────────────┘  └────────┬───────┘   │  Integrations   │
                                  │           │  IPC drainer    │
                                  └───────────│  Runtime        │
                                              │  ──────────────│
                                              │    DorisIPC     │
                                              │  Wire types     │
                                              │  HMAC           │
                                              │  Keychain       │
                                              │  Darwin notify  │
                                              └─────────────────┘
                                                      ▲
                                                      │
                                                ┌─────┴────┐
                                                │ doris CLI│
                                                │ (ArgParser)│
                                                └──────────┘
```

`DorisCore` ships two library products in one Swift package:

- `DorisIPC` — pure Foundation + CryptoKit, no SwiftData, no UI. The
  CLI, share extension, intents handler, and tests all build it stand-
  alone via `swift build`.
- `DorisCore` — SwiftData models, sync, integrations, settings.
  Depends on `DorisIPC`.

`DorisUI` is **cross-platform** (Mac + iOS) — the Today components,
note editor, tag chips, day-collapsible event list, voice floater are
all shared. `DorisMacChrome` is the Mac-only chrome (anchored notch
panel, hot-side window adapter).

The integrations layer (`DorisCore/Integrations/*.swift`) is
**macOS-only** — wrapped in `#if os(macOS)`. iOS has no analogue of
~/.claude/settings.json hook injection.

## Lifecycle — Mac

1. `DorisAppDelegate.applicationDidFinishLaunching` sets up the
   SwiftData container, ensures the App Group keychain secret, wires
   the notification router, kicks off `SyncTimer`, registers the
   `doris://` URL handler.
2. The router fans in from three sources:
   - `IPCInboxDrainer` (file-drop queue from CLI / share extension /
     intents)
   - `IPCFSEventReader` + `DarwinNotify` (low-latency wake when an
     external writer drops a file)
   - `SilentPushHandler` (cross-device CloudKit notifications)
3. Output fans out to:
   - SwiftData (always: every notification is persisted as a `Message`)
   - `DorisPresenter` — banner via the anchor notch panel
   - `OutboxPublisher` — when broadcast is `allDevices` or `device(…)`

The voice subsystem (`apps/doris-mac/Doris-macOS/Voice/`) is wired
separately:
- `HotkeyEngine` listens for global modifier hotkeys
- On long-press start → `SpeechRecognizer` begins
- On release → transcript handed to `AppRouter` which activates the
  bound app (ChatGPT / Claude desktop / Cursor / frontmost) and
  pastes via synthesised ⌘V

The integrations subsystem reads provider statuses from
`IntegrationsRegistry` (DorisCore). Claude Code reads/writes
`~/.claude/settings.json`. Codex reads/writes the user's shell rc file
(`~/.zshrc` / `~/.bashrc` / `~/.config/fish/config.fish`) with a
marker-delimited block.

## Lifecycle — iOS

1. `DorisAppDelegate.application(_:didFinishLaunching…)` sets up the
   same SwiftData container — the CloudKit mirror is the only sync
   path on iOS (no IPC drainer, no notification banner UI, no voice
   hotkeys).
2. `RootTabView` shows four tabs: Today / Notes / Events / Settings.
   The Today + Notes + CalendarTimeline + day-collapsible event list
   come from `DorisUI`, so they look identical to the Mac main window.
3. Sync polling timer ticks once a minute, same as Mac.

## Cross-device push

```
device A: doris notify --all-devices ...
   → IPCWriter file in App Group inbox
   → Router (persists Message + outbox publish)
   → CloudKit OutboxZone CKRecord write

device B: APNs silent push
   → SilentPushHandler.handleRemoteNotification
   → fetch CKRecord
   → re-route through NotificationRouter (broadcast=.local on receiver
     to prevent loops)
```

Origin device dedup uses `originDeviceId` on the outbox record;
receivers ignore their own broadcasts.

## File / disk layout (App Group)

```
~/Library/Group Containers/group.com.gavin.doris.shared/
├── IPC/
│   ├── inbox/          ← CLI / extension drops
│   ├── outbox/         ← app → CLI replies (e.g. inbox tail)
│   └── processed/      ← archived requests, .ok / .error / .rejected suffix
├── Attachments/        ← <uuid>.<ext> binary blobs
├── Backups/<yyyymmdd>/ ← snapshot copies of the SwiftData store
├── Logs/doris-debug.log ← (future) rotating log
└── Store/              ← SwiftData SQLite + journal + CK metadata
```

iOS has the same App Group container, but no extension writers (no
IPC subdirs in active use). The Store/ subdir holds the local
SwiftData store + CloudKit mirror metadata.

## Why the unusual pieces

- **Two libraries (`DorisIPC` + `DorisCore`) inside one Swift Package**:
  the CLI must build without SwiftData macros (which require Xcode).
  Splitting keeps everything compilable from `swift build` for the
  parts that don't touch SwiftData.
- **File-drop IPC instead of XPC or loopback HTTP**: works whether the
  app is running, requires no extra entitlement
  (`network.server`), and the team-scoped App Group container
  provides authentication on top of HMAC.
- **Raw CloudKit for the Outbox, SwiftData+CloudKit for everything
  else**: SwiftData's auto-sync is great for ambient data, but
  cross-device push needs immediate-fire silent-push subscriptions on
  a known record type, which is easier with raw
  `CKModifyRecordsOperation`.
- **Soft-delete tombstone pattern for archived/deleted notes**:
  `ctx.delete()` on a SwiftData CloudKit-mirrored store races against
  other devices' uploads. Pre-1.0 users hit "I deleted these, they
  came back." The fix: bulk-delete paths now set `deleted = true` +
  stamp `deletedAt`; `SyncTimer.purgeTombstones` hard-deletes after
  the soft-state has had time to propagate (24 h for trash,
  30 days for archive). See `SyncTimer.swift` for the long write-up.
- **Production CloudKit env for both Mac DMG and iOS TestFlight**:
  Developer ID and Apple Distribution certs both default to
  Production. Means data syncs between platforms out of the box,
  but also means schema changes must be **explicitly deployed** from
  Development → Production via the CloudKit dashboard (see
  `cloudkit-schema.md`).
- **Day-collapsible event list shared across surfaces**: every event
  surface (anchor popup, main window, iOS tab) reuses
  `DayCollapsibleEventList` from DorisUI. Today is fetched eagerly;
  past days surface only when they actually have events (`fetchCount`
  probe on appear) and expand to load full row data on demand.
