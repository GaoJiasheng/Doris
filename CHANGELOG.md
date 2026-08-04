# Doris — Changelog

Versions follow [semver](https://semver.org). `MARKETING_VERSION` in
`project.yml` is the single source of truth; bump it before running
`scripts/release.sh` to cut a release.

---

## 1.8.0 — 2026-08-04

The first release with a website: <https://doris.gavin.pub>. Everything
below shipped in 1.7.x builds that were never published as releases, so
this is where they actually reach you.

### Added

- **A visible focus button on every task row.** Starting a pomodoro was
  buried in the right-click menu, while sub-tasks had a ▷ button all along.
  Idle it offers 15 / 25 / 45; running on that task it becomes a stop
  button, and it stays visible (unlike the hover-only archive/delete pair)
  because it doubles as the "which task am I on" indicator.
- **Double-click a task row — or press ⌘↩ — to open it.** The toolbar
  button stays. Costs in-row double-click-to-select-word.

### Changed

- **macOS task rows are easier to hit.** The title was 11pt (`.subheadline`
  resolves to 11 on macOS, 15 on iOS); it's now 14pt, which also gives a
  taller caret to aim with. And because an `NSTextField` is exactly
  text-high, the row's padding used to be dead space — clicking just above
  the glyphs did nothing. The field now owns that padding, roughly doubling
  the editable area without making rows much taller.
- **A rebuilt due-date picker.** Presets first (today / tomorrow / weekend /
  next week), then a calendar drawn in-app. macOS's `.graphical` DatePicker
  keeps its own intrinsic size, draws a blue system bezel that reads as an
  error box on a dark panel, and gives ~11pt day cells — none of it
  reachable from SwiftUI.

### Fixed

- **Pinyin (and any marked-text IME) input on iOS.** Composition kept
  collapsing to raw letters mid-word, as if Return had been pressed. Three
  causes, all "a view rebuild commits the input method's buffer": the
  checklist field assigned its text on every update pass, its coordinator
  published half-composed text upward, and every keystroke in a title
  re-sorted the notes query that the open editor was resolved from.
- **A long-press could leave a pinned card as an empty dashed outline** for
  the rest of the session — the drag state cleared only when a card was
  dropped *onto another card*, and on iOS a long-press alone starts a drag.
- **Due dates picked in the popover never scheduled a reminder.** They set
  the date without telling `DueDateNotifier`; only the right-click menu did.

## 1.7.1 — 2026-07-28

### Fixed

- **A long-press could turn a pinned card into an empty dashed outline for
  the rest of the session.** Starting a drag hid the card (its snapshot is
  what follows your finger, so the slot becomes a gap), but the state that
  hid it was only cleared when the card was dropped *onto another card*.
  Release anywhere else — in the space between cards, outside the grid, or
  without moving at all — and the card stayed invisible until the app was
  restarted. On iOS a long-press alone begins a system drag, so simply
  pressing and letting go was enough to trigger it. Drops that miss a card
  are now caught by a backstop behind the grid, and a drag that never
  reports a drop (cancelled, or released outside the app — the system gives
  no callback for either) times out and restores the card.

## 1.7.0 — 2026-07-28

Token stats now count your local LM Studio models.

### Added

- **LM Studio token usage.** Both the GUI chats and — more usefully — every
  request served by LM Studio's local server. The server is the layer
  everything funnels through, so this counts your own code, the `lms` CLI,
  and any agent pointed at `localhost:1234`, not just the app's own chat
  window. Cost is 0 (they run on your Mac); the point is volume.
  - GUI chats come from `~/.lmstudio/conversations/`. There's no per-message
    date in that file, but each step's id is `<epochMillis>-<random>`, so
    generations land on the day they actually happened rather than being
    smeared onto the conversation's last-modified date.
  - Local-server usage comes from `~/.lmstudio/server-logs/`, where each
    answered request is logged with an OpenAI-shaped `usage` block. This
    requires LM Studio's **File Logging Mode set to `full`** — on the default
    `succinct` the response bodies are never written. Doris says so in the
    source's status row instead of quietly counting nothing.
  - The two can't double-count: GUI chats don't travel over the HTTP server.

### Fixed

- **A source added in a later version stayed invisible.** The set of enabled
  token sources is persisted, so an install that predated a new adapter never
  had it in its set — you'd upgrade and simply see no data, with nothing
  explaining why. Zero-config sources are now switched on the first time an
  install sees them; a source you deliberately turned off is never
  re-enabled.

## 1.6.2 — 2026-07-27

iCloud sync fixes. If you have both a Mac and an iPhone, this is the
important one — inbound sync on iOS never worked, and the app said it did.

(1.6.1 was cut for the first fix below but superseded before release.)

### Fixed

- **iOS never received changes from other devices.** SwiftData's CloudKit
  mirror imports remote changes only when a subscription push wakes it, and
  the iOS app had none of what that requires: no `aps-environment`
  entitlement (so APNs could not deliver to it at all), no
  `remote-notification` background mode, and no registration call. Notes
  archived, unpinned, or created on the Mac simply never arrived — one
  unpinned note was a month stale — and neither waiting nor relaunching
  helped, because there was no inbound path to wait for. macOS had all of
  this from the start, which is why only the phone drifted.
- **"Sync succeeded" was reported without checking whether syncing worked.**
  Success meant "the local save worked and the iCloud account is reachable"
  — never that anything was exchanged. So the phone showed a healthy green
  status the entire time it was silently ignoring the cloud. Now a poke
  fails loudly when iCloud is on but the store isn't actually mirroring, or
  when this device can't receive pushes (so remote edits can't arrive), and
  with sync off it no longer stamps a "last synced" time for what was only
  a local save.
- **iCloud sync now defaults to ON.** It defaulted to OFF and the only
  automatic way to enable it was a *shell* environment variable
  (`DORIS_USE_CLOUDKIT=1`) — which cannot exist for an app launched from the
  home screen or Finder. A fresh install therefore had sync silently off.
  Existing choices are respected: only installs that never touched the
  toggle change. `DORIS_USE_CLOUDKIT=0` still forces it off for development.

### Notes

- A degraded container is now distinguishable from user intent:
  `SyncSettings.cloudKitEnabled` is what you asked for,
  `DorisRuntime.cloudKitActive` is what you actually got. Every sync
  indicator used to read the former, which is how "iCloud on" could display
  over a local-only store.

## 1.6.0 — 2026-07-26

Focus (pomodoro) on both platforms — highlight what you're doing right now.

### Added

- **Focus timer.** Start a 15 / 25 / 45-minute focus on any task *or*
  sub-task (right-click a task, or the ▷ button on a checklist row). One
  session at a time — this is a "what am I on right now" highlighter, not a
  stats tool. No history, no charts, no schema change: the session lives in
  memory + UserDefaults and survives a relaunch.
- **macOS: a countdown ring in the notch.** On a notched display the ring
  sits opposite the avatar, symmetric across the camera cutout; on any other
  screen edge it shares the avatar's tab, so the pair drags as one panel with
  one background and one opacity. Hover for the task name, click to jump
  straight to the task (a sub-task focus also drops the caret on that
  checklist line), right-click for duration / pause / stop. Clicking the
  avatar itself is unchanged.
- **macOS: the focus overlay follows the character.** Pull the avatar out to
  the desktop and the task name + countdown layer over the animation.
- **iOS: a full-screen dial.** Starting a focus opens one big ring with the
  clock inside it and a small ✕ to close. Closing leaves the clock running —
  a compact chip brings you back.
- **Ring states.** Running shows the remaining minutes inside the ring,
  paused dims it and shows `II`, finished turns it into a green check.
- **When a session ends** you're offered: keep going for another 5 / 15 / 25
  minutes, exit, or complete the task (which marks the task done, or ticks
  the focused checklist line).
- **Pause / resume.** Holding the clock freezes the remaining time rather
  than trusting the wall clock, so a paused session stays paused across a
  relaunch.

### Fixed

- **iOS showed trashed notes.** Today, the notes list, and the calendar
  timeline filtered out archived notes but not *trashed* ones — and since
  delete is a soft-delete (recoverable from Trash), anything you deleted kept
  showing up. Most visible as a pinned count that disagreed with macOS
  (which has always filtered both), which looked like a broken iCloud sync
  but wasn't: the data was in sync the whole time, iOS was just drawing rows
  it should have hidden.
- **macOS: an exit from the "focus done" prompt.** A completable task offered
  only Again / Break / Done — there was no way to dismiss the prompt without
  marking the task complete.

### Notes

- On iOS the end-of-session alert is a scheduled local notification, not an
  in-app timer callback: the 1 Hz countdown stops as soon as iOS suspends the
  app, so a phone locked to help you focus would otherwise never be told the
  session was over.

## 1.5.1 — 2026-07-14

A large CPU / energy fix, plus iOS checklist keys matching macOS.

### Fixed

- **Big CPU / energy drop.** The animated avatar and the shared window
  backdrop were redrawing every display frame even when idle or hidden —
  pinning a CPU core near 100% and tripping the macOS "using significant
  energy" warning. Now: the avatar pauses when its window is hidden or
  occluded and skips its particle effects in the compact sidebar, and the
  backdrop's halo + scanlines are static instead of animating continuously.
- **iOS checklist keys.** In a checklist note, **Return** adds a new item and
  **Backspace on an empty item** deletes it / merges into the previous row —
  matching macOS. Long items wrap; multi-line paste stays in one item.

## 1.5.0 — 2026-07-02

A hands-on desktop panel, plus the fixes that landed after 1.4.0.

### Added

- **The desktop panel is now interactive.** Tap a task's title to open it in
  place and edit its sub-tasks and text (the row was previously read-only
  apart from the done circle). A new control in the panel header adds an
  **opacity** slider (fades just the background, so tasks stay readable) and
  an **always-on-top** toggle. With always-on-top off, clicking the panel
  "peeks" it above other windows and it recedes when you click away.

### Fixed

- **Desktop panel no longer disappears** after the app relaunches or updates
  (closing it on quit was wrongly treated as "hidden by the user").
- **App icon** is always the default Cyber Cat on macOS (Dock) and iOS,
  regardless of the selected character pack.
- **Cross-mood avatar alignment** calibrated for every character pack, so the
  avatar no longer shifts position when it switches moods.
- **Codex token usage** no longer under-counts long sessions — the dedup key
  is now content-stable, with a one-time re-scan to recover lost history.
- **Tokens dashboard** keeps the cost column on a single line.
- Removed the recurring macOS "Doris wants to access data from other apps"
  prompt on Claude / Codex task completion (the CLI↔app inbox moved out of
  the App-Group container to `~/.doris`).

## 1.4.0 — 2026-06-22

Swappable characters, a lighter Today, and a trimmer token monitor.

### Added

- **Swappable characters.** Three full character packs — **赛博猫 / Cyber Cat**
  (the new default), **赛博·女孩 / Cyber Girl**, and **回形针 / Clip** — each ships a
  seven-mood animated avatar, a menu-bar / notch mark, an app icon, and its own
  light/dark color theme. Switch in Settings → Appearance → Character; the
  avatar, notch mark, Dock icon, and theme all change together.

### Changed

- **Today token-usage glance** is now a borderless gradient headline instead of
  a boxed card, with the local weather — condition, temperature, location —
  filling the right side.
- **Main window:** the avatar / detail split divider is draggable to resize the
  panes, and window-dragging is scoped to the header strip.
- **App icons** (macOS + iOS) now show the default Cyber Cat.

### Removed

- **Subscription-quota estimate.** The remaining-% / 5-hour-cap estimate and the
  Claude Code status-line capture are gone — they were never reliable. Token
  *usage* tracking (consumption + cost, by tool and model) is unchanged.

---

## 1.3.0 — 2026-06-21

Token usage monitor + a unified, borderless main window.

### Added

- **Token usage monitor (macOS).** Tracks token consumption across local AI
  CLIs (Claude Code, Codex) by parsing their on-disk logs — a home summary
  card (today's tokens + cost) and a full **Token** dashboard tab (today /
  7-day / 30-day / all-time totals + a per-day trend). Parsing follows
  ccusage's model: dedup on the `message.id`+`requestId` composite and scans
  both `~/.claude` and `~/.config/claude`. Cost is computed from per-model
  rates.
- **Subscription quota.** The Token dashboard shows the rolling 5-hour
  window. Opt into the **status-line capture** (Settings → Token) to surface
  Claude Code's real 5h + weekly remaining-% — the only supported source;
  otherwise it shows a usage estimate.

### Changed

- **Unified, borderless main window.** The main window and the expanded
  notch/pet dropdown are now one surface (avatar sidebar + tabs + Token),
  with mode-specific behavior: summoned from the notch/pet it opens beside
  the pet and dismisses on focus-loss; opened via "Open Main Window" it
  centers and stays until closed. Each mode remembers its own size. The
  window is borderless — a custom close button replaces the traffic lights,
  and Cmd-W closes it.
- **Long task / sub-task titles wrap** to show their full text instead of
  truncating to a single line.

### Fixed

- Main-window header tabs (and the sync / theme controls) were unclickable
  on macOS 26 (Tahoe); the header is reworked so they register clicks again,
  with no empty band above it.
- No more flash of the old dropdown at every launch.

## 1.2.2 — 2026-06-20

Faster iOS widget refresh + groundwork for swappable characters.

### Fixed

- **iOS widget refreshes closer to real-time after an edit.** 1.2.1 only
  asked WidgetKit to reload on the 60-second sync tick, on foreground, or
  at background-time — and a reload requested *as the app suspends* is the
  one iOS defers most, so an edit-then-leave still updated the widget only
  "a while later." The app now front-loads a (debounced) reload the instant
  data is saved, while it's still foreground — WidgetKit honors
  foreground-initiated requests far sooner. (iOS still ultimately schedules
  widget refreshes; this minimizes the part the app controls.)

### Internal

- **Character-pack framework (dormant).** Groundwork for swappable visual
  identities — animated character, portrait, pixel notch mark, and per-pack
  app icon (macOS Dock + iOS alternate icons). No user-facing change yet:
  only the built-in "小姑娘" ships, and the picker stays hidden until a
  second pack is added.

---

## 1.2.1 — 2026-06-13

Bug-fix release: the iOS home-screen widget now actually keeps up.

### Fixed

- **iOS widget no longer goes stale after an in-app sync.** Two causes:
  (1) the app asked WidgetKit to reload on *every* 60-second sync tick
  (plus every foreground/background) regardless of whether anything
  changed — exhausting WidgetKit's limited daily reload budget, so the
  one reload that mattered (right after you edit/sync) got throttled
  away; (2) the sync path saved a throwaway empty `ModelContext` instead
  of the live one, so edits reached the shared store only via autosave.
  Now a `WidgetReloadCoordinator` reloads **only when the widget-visible
  data actually changed** (a deterministic signature over pinned + dated
  notes), the sync path saves the live context, and a manual **"Sync
  Now" / pull-to-refresh forces an immediate widget reload**.

---

## 1.2.0 — 2026-06-11

Doris gets a personality — she reacts to your work, runs a little daily
ritual, and the desktop surfaces gain day/night moods.

### Added

- **The avatar reacts to your tasks.** She **celebrates** when you
  complete a task (or finish the last item of a checklist), **greets you
  once per day** the first time you open the app (morning ritual), and
  **looks alerted** when an agent banner appears. All reactions are
  gated by a new **Avatar activity** setting — **安静 / 标准 / 活泼**
  (quiet silences reactions; lively lets the small ones through too).
- **Due-date reminders.** Notes with a due date schedule a local
  notification at 09:00 on the day they're due — Doris "递纸条" so a
  deadline doesn't slip by. Cleared automatically when you complete or
  un-set the date. (macOS + iOS.)
- **Arrow-key row navigation in the macOS task list.** Press **↑ / ↓**
  while editing a task title to move the cursor between rows.
- **Open the main window from the desktop panel.** Click the panel's
  "Doris · 今日" title or the new window button in its header.

### Changed

- **Day/night avatar backdrop.** The cartoon's backdrop now follows the
  白天/夜间 (light/dark) theme: a daytime sky (sky-blue → pale horizon
  with a soft sun glow, starfield faded to faint dust motes) in light
  mode; the original deep-space night + full starfield in dark mode.
- **Light-mode contrast pass.** Neon pink/cyan are deepened in light
  mode for legibility, and the glow is made scarce — secondary panels
  (sticky notes, desktop panel) now use a dimmer stroke so the
  full-brightness glow reads as meaningful, not decorative.
- **Settings decluttered.** Removed dead toggles that no longer did
  anything (hex color preview, auto-backup daily, hot side, open bar).
- **iOS reloads widgets on backgrounding** so leaving the app after an
  edit gives a fresh widget immediately.

### Fixed

- **macOS Enter no longer creates a duplicate row.** A stale Return
  keypress could land on the freshly-focused new row and spawn a second
  empty task; a short debounce on row creation closes that race.

---

## 1.1.2 — 2026-06-08

Tactile Today cards, a more elegant widget, and sturdier task editing.

### Added

- **Live drag-reorder for pinned cards** (iOS + macOS, shared
  `ReorderableNoteGrid`). Drag a 置顶 / 长期 card and its neighbours
  **slide out of the way under your cursor** (spring-animated, reorder on
  hover); the dragged card leaves a dashed gap and the order persists on
  release. Replaces the old reorder-only-on-drop behavior.

### Changed

- **iOS Tasks widget redesign ("Calm Focus")** — hero count/date ledger
  header, a calm hairline-divided list with quiet accent dots, a 16pt
  checklist progress ring, LED section dots, and a rebuilt
  vibrancy-safe lock-screen layout. Tap-to-complete + all families kept.
- **macOS task & checklist editing** now uses AppKit-backed fields so
  the field editor's keys are interceptable: **Return** adds a new row
  directly below (cursor at its start); **Backspace on an empty row**
  deletes it and lands the cursor at the end of the previous row. New
  top-level tasks position by `order` so Enter always inserts below the
  current row, even after a drag.
- **iOS notes list decluttered** — sync status shows minute granularity
  (no live-ticking "X sec ago"); rows drop the running relative time;
  the note's creation time (to the minute) moves to the detail page.

### Fixed

- **iOS widgets read the local App-Group store directly**
  (`useCloudKit: false`). Standing up CloudKit inside a widget extension
  overran the CPU budget, couldn't finish a fetch before suspension,
  trapped on unsigned builds, and left the widget stale. The app owns
  the CloudKit mirror and now reloads the widgets on every sync tick and
  on app foreground.

### Known issues

- A macOS-only "Enter creates two rows" in the TODO list is under
  investigation (does not affect iOS).

---

## 1.1.0 — 2026-06-03

Desktop surfaces everywhere — float your tasks onto the Mac desktop and
onto the iPhone home/lock screen — plus a richer Today and a sturdier
agent-integration layer.

### Added

- **macOS desktop sticky notes** — right-click any note → **贴到桌面 /
  Stick to desktop** to float an editable mini-window above your desktop
  (`StickyPanel`, borderless non-activating `NSPanel`). It remembers the
  size you drag it to; closing and re-sticking resets to the default
  300×300. Stickies are device-local (not synced).
- **macOS always-on-desktop dashboard panel** — a compact, live
  (`@Query`) list of 置顶 / 长期 / 日程 tasks with inline tap-to-complete.
  Toggle it in Settings → 窗口 / 外观.
- **iOS Tasks widget** — home-screen + lock-screen widget showing 置顶 +
  日程 with **tap-to-complete** via an interactive `AppIntent`
  (`ToggleTaskIntent`), capability-matched to the macOS desktop panel.
  Joins the existing Events widget in the widget bundle.
- **Today — 长期 / Long-term bucket** — a third pin tier (alongside 置顶)
  for things you keep around indefinitely, with its own violet accent +
  ∞ icon. Right-click toggles 置顶 ⇄ 长期 (mutually exclusive).
- **Drag-to-reorder pinned cards** — pinned/long-term cards drag to
  reorder on both macOS and iOS; the order persists (`Note.order`) and
  syncs via CloudKit.
- **Collapsible cartoon assistant** — the dropdown + main-window avatar
  pane folds away, with a default-visibility setting ("显示卡通助手"). The
  dropdown pane auto-hides when the panel is dragged too narrow so the
  collapse control never clips.
- **Checklist sub-task progress on Today cards** — pinned cards now show
  live `done/total` from the note's markdown checklist.

### Changed

- **Checklist editor UX** — long items wrap instead of scrolling
  (macOS uses an AppKit-backed self-sizing field); Enter creates a new
  item with the cursor already inside it; Backspace on an empty item
  deletes it and merges the cursor into the end of the previous one.
  Completion is a *trigger*, not a forced state: ticking the last item
  completes the note, un-ticking reopens it.
- **Completion model centralized** — note-level done + "all checklist
  items ticked" fold into one `Note.isCompleted` helper, fixing
  surfaces that read the dead legacy `checklistItems` relationship.
- **Notification banners carry the agent's brand logo** — Claude Code /
  Codex completions show the real Claude / Codex icon instead of the
  Doris avatar, and stay on-screen +2s longer so "task done" is
  catchable.
- **Desktop surfaces share one visual language** — sticky notes, the
  desktop panel, and the iOS Tasks widget all use the adaptive cyber
  gradient + pink/cyan corner glow, per-section accent rails, and
  checklist progress pills.

### Fixed

- **Integrations wrote into the sandbox jail** — `register()` for Claude
  Code / Codex resolved `~` to the app's sandbox container
  (`~/Library/Containers/com.gavin.doris/Data/`), so the hook landed in
  a fake `.codex` / `.claude` the real tools never read. Now resolves
  the *real* home via `getpwuid`, gated by a
  `temporary-exception.files.home-relative-path.read-write` entitlement
  scoped to `/.codex/` + `/.claude/`.

### Internal

- New `apps/doris-mac/Doris-macOS/Sticky/` module: `StickyStore`,
  `StickyNoteView`, `StickyWindowManager`, `DesktopPanel*`.
- New `apps/doris-ios/DorisWidget-iOS/TasksWidget.swift` with the
  `ToggleTaskIntent` interactive intent.
- `Note.longTerm` is a new synced field — **redeploy the CloudKit
  Production schema** so it syncs cross-device (see `docs/release.md`
  step 7). Sticky/panel/avatar visibility state is deliberately
  device-local (UserDefaults), not a synced field.

---

## 1.0.0 — 2026-05-31

First stable release. Mac ships as a Developer-ID-signed download; iOS
ships to TestFlight against the same Production iCloud container.

### Added

- **Today + calendar surfaces** ported across all three views (mac main
  window, mac dropdown popup, iOS) from one shared component set, with
  day-collapsible event lists and TODO due-date chips.
- **App integrations registry** (Settings → 应用集成) with one-click
  auto-register for **Claude Code** (`~/.claude/settings.json` Stop
  hook) and **Codex** (native `notify` hook in `~/.codex/config.toml`
  wired to a Doris dispatcher — works for the Codex desktop app *and*
  CLI; the earlier shell-rc-wrapper, terminal-only, was replaced).
- **`doris` CLI embedded + signed inside Doris.app**, with a first-run
  wizard to symlink it into PATH; CLI manual bundled as a PDF in the
  download.

### Changed

- **Notification UX overhaul** — half-height banners, tighter corners,
  `reminder` default level, banner-click opens the source app.
- **Full localization pass** (English ⇄ 中文) across Settings, sidebar,
  wizard, and lists via the shared `L()` helper.
- **Sync feedback parity** between Mac and iOS; CloudKit gated behind a
  code-signing check so unsigned dev builds no longer crash on launch.

### Fixed

- **CloudKit hard-delete race** — soft-delete tombstone pattern
  (`SyncTimer.purgeTombstones`) so deletions converge across devices.
- **Claude Stop hook** emitted `--click` (unknown to the CLI), exiting
  64 every session — now `--click-url`.

---

## 0.2.0 — 2026-05-21

First Developer-ID-signed + notarized release. Ready for distribution
via DMG download.

### Added

- **App integrations** (Settings → 应用集成): pluggable
  `IntegrationProvider` framework so Claude Code / Codex / ChatGPT
  task-completion notifications route through Doris instead of macOS
  Notification Center.
  - Claude Code: full automatic registration via
    `~/.claude/settings.json` Stop hook.
  - Codex / ChatGPT: `.manual` tier with tutorial links until those
    tools expose hook APIs.
- **`doris://notify` URL scheme** for triggering banners from
  `open doris://notify?title=...&source=...&click=...`. Useful for
  Shortcuts / web bookmarklets.
- **CLI man page** at `docs/cli-manual.md`, also bundled as PDF in
  the shipped DMG.
- **Doris CLI embedded inside Doris.app** at
  `Contents/Resources/doris`, signed with the team's Developer ID +
  hardened runtime + cli.entitlements (App Group only, no sandbox).
- **TODO row due-date chip** replaces the modified-at relative time;
  smart labels (今天 / 明天 / 周X / 5月20日), color-coded by urgency,
  click-to-open date picker.
- **Today tab** on mac main window + dropdown popup, mirroring iOS.
  Shared `TodayPinnedCard` / `TodayCalendarRow` across all three
  surfaces.

### Changed

- **Banner cards halved** in height (84pt → 42pt for auto-dismiss,
  108pt → 54pt for fix-mode), corner radius 22 → 10 (overall
  rectangular shape, lightly rounded).
- **Click-to-open** on a banner now opens the source app via its URL
  scheme (`claude://`, `chatgpt://`, etc.) using
  `NSWorkspace.OpenConfiguration.activates = true` — previously
  collapsed Doris's own dropdown instead.
- **Default integration level** raised from `info` (1.5s) to
  `reminder` (4s + orange progress bar) — info disappeared before
  the user could react to "task done".
- **Today tab section colors swapped**: pinned now pink (warm /
  attention), upcoming now cyan (calmer / scheduled).
- **Localization pass**: every Settings tab item, label, button, and
  toggle now flips between English and 中文 via the shared `L()`
  helper.
- **Hook command bug fix**: was emitting `--click` (unknown to the
  CLI), now `--click-url` — Claude Stop hooks were silently exiting
  64 every session before the fix.

### Internal

- Release pipeline: `scripts/release.sh` builds, signs, notarizes,
  and packages the DMG end-to-end via App Store Connect API key
  (`~/.appstoreconnect/private_keys/AuthKey_*.p8`).
- Provisioning: 5 bundle IDs auto-managed via
  `-allowProvisioningUpdates` with the team's Mac device registered
  for the Apple Development cert path.
- `docs/release.md` walks through the one-time signing setup.

---

## 0.1.0 — Initial pre-release

Foundation: SwiftData store, anchor + dropdown UI, IPC inbox/outbox,
CLI scaffold, CloudKit sync (when properly signed), iOS app, share
extension, widget, App Intents.
