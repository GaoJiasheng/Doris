# Doris

A native **macOS + iOS** notes, tasks, and agent-notification companion. A
menu-bar / notch helper on the Mac and a full editor on iPhone, sharing one
iCloud-synced store — it replaces a paid SideNotes-style sidebar with
cross-device push, agent task-completion banners, desktop widgets, and a CLI
bridge.

## What it does

- **Notes & tasks** — plain notes and checklists in one editor. Checklists
  show live sub-task progress; ticking the last item completes the note (and
  un-ticking reopens it). Long items wrap, Enter makes a new item with the
  cursor already in it, Backspace on an empty item merges into the previous.
- **Today** — a focus surface with three buckets: **置顶 / Pinned**,
  **长期 / Long-term** (things you keep around indefinitely), and
  **日程 / Upcoming** (due-dated). Pinned cards drag to reorder and the
  order is remembered + synced.
- **macOS desktop surfaces** — pin any note as a floating **desktop sticky**
  (remembers its size; resets to default when re-stuck), or keep an
  always-on-desktop **dashboard panel** of pinned + today's tasks with inline
  tap-to-complete. Both are toggleable in Settings.
- **iOS widgets** — home-screen + lock-screen **Tasks** widget (置顶 + 日程,
  with tap-to-complete via an interactive App Intent) and an **Events** widget,
  capability-matched to the macOS desktop panel.
- **Agent notifications** — route **Claude Code** and **Codex**
  task-completion notifications through Doris instead of macOS Notification
  Center. One-click register in Settings → 应用集成; banners carry the real
  Claude / Codex brand logo so a glance tells you which agent finished.
- **The cartoon assistant** — a menu-bar / notch character (collapsible, and
  width-responsive in the dropdown) that reacts to clicks and notifications.
- **Cross-device** — minute-level iCloud (CloudKit) sync across every Mac and
  iPhone signed into the same Apple Account, plus a `doris` CLI for firing
  notifications and adding notes from scripts.

See [plan/v1-design.md](plan/v1-design.md) for the v1 architecture and [docs/](docs/) for module-level docs.

## Repo layout

```
project.yml                  XcodeGen spec — one source of truth for all targets
apps/doris-mac/               macOS app + Share + Widget extensions
apps/doris-ios/               iOS/iPadOS app + Share + Widget extensions
extensions/DorisIntents/      App Intents (Add Note, Push Notification, …)
cli/doris/                    `doris` command-line binary (Swift Package)
packages/DorisCore/           SwiftData models + CloudKit sync (DorisCore product)
                             plus pure-Foundation IPC types (DorisIPC product)
packages/DorisUI/             Shared SwiftUI views
packages/DorisMacChrome/      Mac-only chrome (DynamicNotchKit, NSPanel, HotSide)
scripts/                     Build / project-generation helpers
plan/                        Design docs
```

## Bootstrap (first time)

```bash
# 1. Install Xcode 16+ from the Mac App Store (iOS 18 / macOS 14 SDKs +
#    interactive-widget App Intents). Command Line Tools alone is not enough —
#    SwiftData macros and SwiftUI #Preview macros need Xcode.
xcode-select -p   # should point at /Applications/Xcode.app/Contents/Developer

# 2. Install XcodeGen.
brew install xcodegen

# 3. Set your Apple Developer team id (used by signing).
export DORIS_TEAM_ID=ABCDE12345

# 4. Generate the Xcode project from project.yml.
./scripts/generate-project.sh

# 5. Open the project, set the team, build the Doris-macOS scheme.
open Doris.xcodeproj
```

## CLI quickstart

After building once, the bundled CLI is at `Doris.app/Contents/Resources/doris` (or `cli/doris/.build/release/doris` for standalone builds). On first launch the app offers to symlink it into your PATH.

```bash
doris notify --title "build done" --body "tests passed" --mode banner
doris notify --title "deploy ok" --mode fix --click-url "https://example.com"
doris notify --all-devices --title "lunch?"
doris note add --title "shopping" --body "milk, bread"
doris inbox dismiss <uuid>
doris sync
doris auth init
doris auth path
```

## Standalone builds without Xcode

`DorisIPC` and the `doris` CLI are pure Swift / Foundation and build with the toolchain shipped via Command Line Tools:

```bash
cd packages/DorisCore && swift build --target DorisIPC
cd cli/doris && swift build
```

Targets that depend on SwiftData (`DorisCore`'s SwiftData product, `DorisUI`, the apps) require Xcode because `@Model` and `#Preview` are external macros not bundled with Command Line Tools.

### Local dev override for the App Group container

When the CLI binary is unsigned (`swift build` debug builds), it cannot resolve the App Group container — `containermanagerd` may block waiting on entitlement checks. Set `DORIS_IPC_ROOT` to a writable directory and the CLI uses that instead:

```bash
export DORIS_IPC_ROOT=/tmp/doris-dev
./cli/doris/.build/debug/doris notify --title "smoke" --no-launch
ls $DORIS_IPC_ROOT/IPC/inbox/
```

Production builds (signed and entitled with the App Group) use the real shared container automatically.

## Architecture at a glance

External script → `doris notify ...` → `<AppGroup>/IPC/inbox/*.json` → `IPCInboxDrainer` → `NotificationRouter` → (a) SwiftData `Message` (synced to CloudKit `MessagesZone`), (b) `DynamicNotchAdapter` for banner/fix display, (c) `OutboxPublisher` for cross-device broadcast. The receiver wakes via `CKQuerySubscription` silent push, fetches the outbox record, and routes it locally.

Full architecture lives in [docs/architecture.md](docs/architecture.md).
