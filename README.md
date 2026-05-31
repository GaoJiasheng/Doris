# Doris

A native macOS + iOS notification, notes, and notch helper. Replaces a paid SideNotes-style sidebar with cross-device push, a CLI bridge, and minute-level iCloud sync.

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
# 1. Install Xcode 15+ from the Mac App Store. Command Line Tools alone is not enough —
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
