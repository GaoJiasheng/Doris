% Doris CLI Manual
% Version 1.1.0
% Generated from `docs/cli-manual.md`

# Doris CLI 使用手册

`doris` is a small command-line companion to the Doris menu-bar app. It
lets shell scripts, agentic tools (Claude Code, Codex), and ad-hoc
invocations push notifications, create notes, and trigger sync — all
routed through the running Doris.app via an App-Group IPC channel.

The binary ships inside the app bundle at
`/Applications/Doris.app/Contents/Resources/doris`. The first-run wizard
(Settings → CLI Install) symlinks it to `/usr/local/bin/doris` so you
can call it from any shell.

---

## Quick start

```bash
# Push a banner notification
doris notify --title "Build succeeded" --source claudeCode

# Same banner, click-through opens Claude.app
doris notify --title "Claude task complete" \
             --source claudeCode \
             --level reminder \
             --click-url claude://

# Drop a note into Doris
doris note add --title "Idea" --body "Try the new layout"

# Verify the CLI can reach the running app
doris auth status

# Self-install into PATH (if the wizard skipped or got missed)
doris install --to /usr/local/bin/doris
```

---

## Global options

Every subcommand also accepts:

| Flag | Effect |
|------|--------|
| `--quiet`, `-q` | Suppress the `doris: queued notification <UUID>` success line. Errors still print. |
| `--help`, `-h` | Per-subcommand help text. |
| `--version` | Print version and exit. |

Exit codes follow `sysexits.h`:

| Code | Meaning |
|------|---------|
| `0` | Success |
| `64` | Usage error (unknown flag, missing required arg) |
| `65` | Bad data (malformed UUID, unknown enum value) |
| `74` | I/O failure (couldn't write to inbox, keychain access denied) |
| `75` | Temporary failure (broadcast scope needs running app and `--no-launch` was set) |
| `77` | Permission denied (App Group container access blocked) |

---

## `doris notify`

Push a notification to the running Doris app. The most-used command.

### Synopsis

```
doris notify --title TEXT
             [--body TEXT]
             [--icon SF_SYMBOL]
             [--mode banner|fix]
             [--source SOURCE_KIND]
             [--level critical|reminder|info]
             [--app-id BUNDLE_ID]
             [--click-url URL]
             [--click-note UUID]
             [--to DEVICE_NAME]
             [--all-devices]
             [--no-launch]
             [--json]
             [--quiet]
```

### Options

`--title TEXT` *(required)*
: Notification title. Single line; longer lines auto-truncate in the
  banner UI.

`--body TEXT`
: Optional body. Rendered as a second line in `fix` mode; suppressed in
  the compact `banner` mode (the card height doesn't have room for it).

`--icon SF_SYMBOL`
: Override the auto-picked icon. Pass any SF Symbol name (`hammer.fill`,
  `bolt.horizontal`, etc.). Defaults to the symbol associated with the
  `--source`.

`--mode banner|fix`
: `banner` (default) auto-dismisses after `--level`'s duration.
  `fix` is sticky — stays on screen until the user clicks or presses
  the X. `critical` automatically uses `fix` mode regardless of this
  flag.

`--source SOURCE_KIND`
: Categorizes the notification so the UI can color/icon it. One of:
  `claudeCode`, `codex`, `chatgpt`, `trae`, `vscode`, `feishu`,
  `cliGeneric` (default), `scheduledJob`, `userMemo`, `share`,
  `manual`.

`--level critical|reminder|info`
: Severity. Drives both how long the banner stays up *and* the visual
  loudness (color, contrast, X button).

  | Level | Duration | Color | Use for |
  |-------|----------|-------|---------|
  | `info` | 1.5s | sky-blue | passive logs, "done" pings |
  | `reminder` | 4s | orange | "task complete", "PR ready for review" |
  | `critical` | sticky | pink + X | "build failed", "needs human now" |

  Defaults to `info`.

`--app-id BUNDLE_ID`
: Free-form identifier for the calling app, e.g. `com.anthropic.claudefordesktop`.
  Carried through in the IPC envelope; used by future per-app routing
  rules.

`--click-url URL`
: URL opened when the user clicks the notification. Use a third-party
  app's URL scheme — `claude://`, `chatgpt://`, `codex://`,
  `vscode://` — to deep-link them. Without this, clicking the banner
  expands the Doris dropdown panel instead.

`--click-note UUID`
: Alternative to `--click-url` — clicking opens the specified Doris
  note in the editor.

`--to DEVICE_NAME`
: Push to a specific device by name (multi-Mac / cross-device push).
  Requires iCloud sync enabled on both ends. Pass a literal UUID for
  exact-device targeting; otherwise the app does a name-based lookup
  on receive.

`--all-devices`
: Broadcast to every device on this iCloud account.

`--no-launch`
: Do NOT auto-launch the Doris app if it isn't already running.
  Default behavior is to launch via `open -a Doris` so the
  notification surfaces immediately.

`--json`
: Read the full payload as JSON from stdin instead of via flags. Useful
  for scripts that already have structured data.

### Examples

Plain banner from a shell script:

```bash
doris notify --title "Tests passed" --source cliGeneric
```

Claude Code Stop hook (this is what `Settings → 应用集成 → 注册`
writes into `~/.claude/settings.json`):

```bash
doris notify --title 'Claude task complete' \
             --source claudeCode \
             --level reminder \
             --click-url 'claude://'
```

Read payload from stdin:

```bash
cat <<EOF | doris notify --title "ignored-when-json-mode" --json
{
  "title": "Webhook fired",
  "body": "build #1234 finished in 2m13s",
  "source": "scheduledJob",
  "level": "reminder",
  "clickUrl": "https://ci.example.com/builds/1234"
}
EOF
```

Sticky alert with X button (no auto-dismiss):

```bash
doris notify --title "Build broken" \
             --body "5 compile errors in DorisCore" \
             --level critical \
             --mode fix \
             --click-url 'vscode://file/Users/gavin/work/doris'
```

---

## `doris push`

Convenience alias for `notify --to <device>` — sets `--mode fix`
and broadcast scope by default, since cross-device pushes usually
warrant the sticky display.

```bash
doris push --to "Gavin's iPhone" \
           --title "Remember to merge" \
           --body "branch claude/foo is ready"
```

All `notify` flags are accepted.

---

## `doris note add`

Create a new note in Doris's local store (mirrored via CloudKit if
iCloud sync is on).

```
doris note add --title TEXT
               [--body TEXT]
               [--body-stdin]
               [--folder NAME]
               [--tag NAME]...
               [--quiet]
```

`--title TEXT` *(required)*

`--body TEXT`
: Markdown body. Both `*italic*` and `**bold**` render, as do code
  fences, headers, links.

`--body-stdin`
: Read body from stdin instead of `--body`. Useful for piping output.

`--folder NAME`
: Place note in a specific folder. Folder is created if it doesn't
  exist.

`--tag NAME`
: Attach a tag. Repeatable: `--tag work --tag urgent`.

### Examples

```bash
# Capture clipboard contents into Doris
pbpaste | doris note add --title "Clipboard snapshot" --body-stdin

# File a quick idea
doris note add --title "Sparkle integration" \
               --body "Investigate auto-updater for shipped builds" \
               --folder "Doris" --tag idea
```

---

## `doris note ls / show / edit / rm`

Stubbed in v1.0.0 — round-trip read responses from the running app
aren't implemented yet. These subcommands emit a clear "not yet
implemented" message and exit 65. Use the app UI for now.

---

## `doris events ls / tail / dismiss / done`

`dismiss` and `done` work today (they're one-way writes):

```bash
doris events dismiss <message-uuid>
doris events done    <message-uuid>
```

`ls` and `tail` need the app's outbox-to-CLI response stream, which
isn't wired in v1.0.0. The same scoping flags will eventually work:

```
doris events ls [--source SOURCE_KIND] [--since-secs N] [--unread] [--limit N]
doris events tail
```

---

## `doris devices ls`

Reserved for the multi-device fan-out feature. v1.0.0 stubbed — use
Settings → Sync in the app to view registered devices.

---

## `doris sync`

Trigger an immediate iCloud sync poke. Same effect as clicking "Sync
Now" in the app, but scriptable:

```bash
doris sync
```

Returns immediately after the IPC enqueue; the actual round-trip with
CloudKit happens inside the app process and reports back via the
sync-status banner.

---

## `doris auth`

Manage the HMAC secret that authenticates IPC messages between the CLI
and the app.

```bash
# Is the secret reachable from this CLI binary?
doris auth status

# Rotate the secret (generates a new one in Keychain)
doris auth init

# Print the App Group inbox path
doris auth path
```

The secret lives in the system Keychain under service
`com.gavin.doris.hmac-secret`. Both the app and the CLI must be signed
under the same team identifier (or the CLI must be the one bundled
inside the app) to read it.

---

## `doris install`

Symlink the running binary into PATH.

```
doris install [--to /path/to/destination] [--force]
```

`--to PATH`
: Where to symlink. Defaults to `/usr/local/bin/doris`.

`--force`
: Replace an existing symlink/file at the destination without
  prompting.

If you installed the app and skipped the first-run wizard, run:

```bash
/Applications/Doris.app/Contents/Resources/doris install
```

The wizard's "Install to ~/.local/bin" button is the no-sudo path on
machines where `/usr/local/bin` is root-owned. Both work; the only
practical difference is whether your shell's `$PATH` already includes
the destination.

---

## How the IPC works (for the curious)

```
┌─────────────┐    1. write JSON      ┌────────────────────────────┐
│  doris CLI  │ ────────────────────▶ │ ~/Library/Group Containers/│
│ (any shell) │                       │  group.com.gavin.doris...  │
└─────────────┘                       │      /IPC/inbox/<file>     │
       │                              └────────────────────────────┘
       │ 2. Darwin notify                            │
       │ "com.gavin.doris.ipc.kick"                  │ 4. read + process
       ▼                                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ Doris.app  (drainer + router + UI)                              │
│   3. wake → drain inbox → present banner / save note / sync     │
│   5. move file to /IPC/processed/<file>.ok|error|rejected       │
└─────────────────────────────────────────────────────────────────┘
```

Every JSON envelope carries an HMAC-SHA256 signature over its
canonicalized body, keyed on the shared secret in Keychain. The app
rejects unsigned or wrong-key envelopes — that's why `doris auth init`
exists for rotating the secret if you suspect leakage.

---

## Troubleshooting

### `doris auth status` succeeds but `notify` fails with "Operation not permitted"

The CLI is ad-hoc-signed and macOS's `containermanagerd` blocks App
Group writes. This happens on debug builds. The shipped binary signed
with the Doris team's Developer ID Application certificate is fine.

### `doris notify` says "queued" but no banner appears

1. Confirm the app is running: `pgrep -f "Doris.app/Contents/MacOS"`
2. Check the inbox isn't stuck:
   `ls ~/Library/Group\ Containers/group.com.gavin.doris.shared/IPC/inbox/`
3. Read the app's log: `log show --predicate 'subsystem == "com.gavin.doris"' --last 1m`

### `claude://` (or any URL scheme) doesn't bring the target app to front

Make sure the target app is installed (`/Applications/Claude.app` etc).
Some apps register their URL scheme only after first launch. Run
`open -a Claude` once and the scheme should work afterward.

### Custom hooks I wrote got overwritten by Settings → 应用集成 → 注册

The integration's `register` function preserves any existing hooks in
`~/.claude/settings.json` — it only adds/refreshes hooks tagged with
the comment marker `# doris-integration`. If yours are missing, check
the file timestamp: maybe a different tool also rewrote it.

---

## Versions

| Version | Notable changes |
|---------|-----------------|
| 1.1.0   | macOS desktop surfaces (floating sticky notes + always-on dashboard panel) and iOS home/lock-screen widgets with tap-to-complete; Today gains a 长期/Long-term bucket + drag-to-reorder pinned cards; checklist editor UX (wrap, Enter-to-new-item, Backspace-merge); collapsible / width-responsive menu-bar assistant; integrations now write the real `~/.codex` + `~/.claude` (sandbox-home fix). CLI surface unchanged from 1.0.0. |
| 1.0.0   | Stable release. Auto-register flows for Claude Code + Codex integrations (Codex wires its native `notify` hook in `~/.codex/config.toml` to a Doris dispatcher — works for the Codex desktop app and CLI alike; an earlier shell-rc-wrapper approach only worked for the terminal CLI and was replaced). ChatGPT integration removed (no callback surface). Mac DMG ships with Developer ID signing + Production CloudKit env; iOS ships via TestFlight against the same Production iCloud container. Day-collapsible event lists across every event surface. CloudKit hard-delete race fix (soft-delete tombstone pattern via SyncTimer.purgeTombstones). |
| 0.2.0   | Notification banner UX overhaul, halved card height, smart click-through, in-app integrations registry, localization pass |
| 0.1.0   | Initial release: notify / note add / events dismiss-done / sync / auth / install |

---

*Last updated: built into release 1.1.0.*
