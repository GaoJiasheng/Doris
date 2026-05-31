# doris IPC wire format

There are **two** ways for an external process to reach the running
Doris.app:

1. **App-Group file-drop IPC** — what `doris` CLI / share extension /
   intents handler use. Authenticated end-to-end via HMAC. The bulk of
   this document.
2. **`doris://` URL scheme** — for tools that can't reach the App
   Group (browsers, Shortcuts, Raycast). Subset of the file-drop API,
   notify-only, no HMAC. Section at the bottom.

---

## 1. File-drop IPC

Files dropped into `<AppGroup>/IPC/inbox/` are JSON-encoded `IPCRequest`
envelopes.

### Filename

```
<unix-ms>-<uuid>.json
```

The unix-ms prefix makes lexicographic sort match arrival order; the
UUID is the request id used for dedup.

### Envelope

```json
{
  "v": 1,
  "id": "AB72D9...uuid",
  "kind": "notify",
  "payload": { ... },
  "hmac": "0a1b2c... hex"
}
```

- `v` — schema version, currently `1`.
- `id` — UUID, used by the router for dedup (across both local and cross-device echoes).
- `kind` — one of `notify`, `noteAdd`, `eventsList`, `eventsDismiss`,
  `eventsDone`, `sync`, `ping`.
- `payload` — discriminated union; see types below.
- `hmac` — lowercase-hex HMAC-SHA256 over canonical JSON (sorted keys) of
  the envelope **with `hmac` set to `null`**, keyed by the App Group
  keychain secret.

### Canonical encoding

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
encoder.dateEncodingStrategy = .iso8601
```

### Payload — `notify`

```json
{
  "title": "build done",
  "body": "tests passed",
  "iconName": "checkmark.seal",
  "displayMode": "banner",
  "source": "claudeCode",
  "sourceAppId": "claude-code",
  "level": "info",
  "clickAction": { "kind": "openURL", "url": "https://..." },
  "broadcast": { "kind": "local" }
}
```

| Field | Type | Notes |
|---|---|---|
| `title` | string | required |
| `body` | string | optional, markdown allowed (single line preferred) |
| `iconName` | string | optional SF Symbol override (e.g. `checkmark.seal`); falls back to `source`'s default icon when omitted |
| `displayMode` | enum | `banner` (auto-dismiss) \| `fix` (sticky, user dismisses) |
| `source` | enum | see `SourceKind` below |
| `sourceAppId` | string | optional bundle id of the producing app — used only for logging/audit |
| `level` | enum | `info` (default) \| `reminder` \| `critical` — drives banner color & duration |
| `clickAction.kind` | enum | `openURL` \| `openNote` \| `runIntent` \| `markDone` |
| `broadcast.kind` | enum | `local` \| `allDevices` \| `device` (requires `deviceID`) |

`SourceKind` values: `cliGeneric`, `claudeCode`, `codex`, `chatgpt`,
`trae`, `cursor`, `vscode`, `feishu`. (`chatgpt` stays valid for the
URL scheme — see end of doc — even though the Settings → Application
Integration row for ChatGPT was removed in 1.0.0.)

`ClickAction` variants:

```json
{"kind": "openURL",   "url": "https://example.com"}
{"kind": "openNote",  "noteID": "AB72D9...uuid"}
{"kind": "runIntent", "intentName": "OpenInboxIntent"}
{"kind": "markDone"}
```

`Broadcast` variants:

```json
{"kind": "local"}
{"kind": "allDevices"}
{"kind": "device", "deviceID": "AB72D9...uuid"}
```

### Payload — `noteAdd`

```json
{
  "title": "shopping",
  "body": "milk\nbread",
  "folderName": "Personal",
  "tags": ["chores"]
}
```

### Payload — `eventsList`

```json
{
  "source": "claudeCode",
  "sinceSeconds": 3600,
  "unreadOnly": true,
  "limit": 20,
  "follow": false
}
```

> **Note (1.0.0)**: the request envelope is implemented but the
> response-stream side (`doris events ls / tail` printing rows to
> stdout) is still stubbed. CLI exits with "not yet implemented" /
> code 65 — use the app UI for now.

### Payload — `eventsDismiss` / `eventsDone`

```json
{"messageID": "AB72D9...uuid"}
```

(Wire-name was `inboxList`/`inboxDismiss`/`inboxDone` in pre-1.0
builds. Renamed when the UI changed from "Inbox" to "Events"; the
storage-side enum value `MessageState.active` still encodes as
`"inbox"` for CloudKit compatibility with older records.)

### Payload — `sync` / `ping`

Empty bodies; the kind alone is the request.

---

## 2. `doris://` URL scheme

For tools that can't reach the App Group (browsers, Raycast, Alfred,
macOS Shortcuts, AppleScript). Handled by
`DorisAppDelegate.application(_:open:)` and routed through the same
`IPCWriter` that file-drop uses — so it's the same end-state, just a
different entry point with no HMAC.

### `doris://notify`

```
doris://notify?title=<title>
              &body=<body>
              &source=<sourceKind>
              &level=<info|reminder|critical>
              &mode=<banner|fix>
              &click=<urlString>
```

| Param | Required | Default | Notes |
|---|---|---|---|
| `title` | ✅ | — | URL-encoded |
| `body` | | empty | URL-encoded; rendered below the title |
| `source` | | `cliGeneric` | One of the `SourceKind` values listed above |
| `level` | | `info` | `info` / `reminder` / `critical` |
| `mode` | | `banner` | `banner` / `fix` |
| `click` | | none | Any URL; opened by `NSWorkspace.shared.open` when the banner is clicked |

Example (paste into Terminal):

```bash
open "doris://notify?title=Build%20done&body=tests%20passed&source=claudeCode&level=reminder&click=claude://"
```

### Other `doris://` routes

| URL | Effect |
|---|---|
| `doris://main` | Bring main window forward |
| `doris://new-note` | Open a new note in the editor |
| `doris://note/<uuid>` | Open the note with that id |
| `doris://intent/<name>` | Run a registered AppleScript intent |
| `doris://sync` | Fire `SyncTimer.pokeNow()` (same as Settings → Sync Now) |

All `doris://` URLs work without Accessibility / AppleScript
permission — they're dispatched by macOS's standard URL scheme
machinery the moment Doris is the registered handler for the scheme.
