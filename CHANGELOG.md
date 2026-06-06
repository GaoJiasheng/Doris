# Doris — Changelog

Versions follow [semver](https://semver.org). `MARKETING_VERSION` in
`project.yml` is the single source of truth; bump it before running
`scripts/release.sh` to cut a release.

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
