# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu-bar app (SwiftUI + AppKit) that turns the MacBook notch into a media/OSD/shelf/notification surface. Deployment target macOS 14, Swift 5 with `SWIFT_STRICT_CONCURRENCY = complete`, bundle id `theboringteam.boringnotch`. Two targets: the sandboxed app and `BoringNotchXPCHelper`, plus a `boringNotchTests` unit-test target.

## Build, test, lint

```bash
open boringNotch.xcodeproj                                  # normal dev loop: Cmd+R
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release build
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' test
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' \
  test -only-testing:boringNotchTests/OTPDetectorTests/testEmojiImmediatelyBeforeAndAfterDigits
xcodebuild -resolvePackageDependencies -project boringNotch.xcodeproj   # after SPM changes
swiftlint --config .swiftlint.yml                           # same invocation CI uses
```

Schemes are gitignored — Xcode autocreates `boringNotch` on first open. Unit tests are **hosted by the app** (`TEST_HOST`), so `xcodebuild test` launches a real menubar instance; UI/system-dependent behavior is not covered by them. For detector-style logic there are host-free regression drivers under `scripts/regression/` that recompile the production type plus the XCTest bodies into a standalone binary (`python3 scripts/regression/pr1057_otp.py --work-dir <tmp>`); anything touching windows or media still has to be verified by running the app.

CI (`.github/workflows/`): `cicd.yml` builds *and* tests on an Xcode 26/27 matrix, `swiftlint.yml` lints PRs into `dev`. Release archive + DMG are CI-only — an admin comments `/release <version>` on a `dev` → `main` PR, which runs `build_reusable.yml` (sign, archive, export, `Configuration/dmg/create_dmg.sh`) and publishes the Sparkle appcast from `updater/appcast.xml`.

## Branch policy

Code PRs base on `dev`, never `main`; docs/metadata-only PRs may base on `main`. `base_ref_check.yml` rejects any PR to `main` touching paths outside its allowlist.

## Conventions (enforced by CI or review)

- No `!`, `as!`, `try!` in new code. SwiftLint demotes them to warnings only for audited legacy sites; a new one needs a comment justifying it plus a config entry.
- Log through `helpers/Log.swift` (`Log.music`, `Log.xpc`, …) — never `print()`.
- Managers publish state/events; only the coordinator/presenter layer decides what the UI shows. Don't call `BoringViewCoordinator.shared` from a hardware/OS-facing manager (see `NotchUIEventBus` below).
- File name matches the primary type it contains. New third-party-derived files carry an SPDX header.

## Architecture

**Window model.** The notch is not a normal window. `NotchWindowManager.shared` (not `AppDelegate`, which only keeps app-lifecycle glue) owns one borderless non-key `NSPanel` *per screen* when `Defaults[.showOnAllDisplays]`, each with its view model and drag detector in a single `ScreenContext` keyed by display UUID — the parallel dictionaries it replaced had to be mutated in lockstep. `NotchBarWindow` (`components/Notch/NotchBarWindow.swift`) is a separate always-black full-width panel at `.mainMenu - 1` for `Defaults[.hideNotch]`. `NotchSpaceManager` puts them in a private `CGSSpace` (`private/CGSSpace.swift`) at max level so they float over fullscreen apps. On the lock screen `BoringNotchSkyLightWindow` (SkyLightWindow package) takes over. Screens are identified by `NSScreen.displayUUID` (`extensions/NSScreen+UUID.swift`), never by name — `BoringViewCoordinator` migrates the legacy name-based preference.

**State.** Three layers, all `ObservableObject`:
- `BoringViewModel` — *per window*: open/closed, size, drop targeting, hover. `open()`/`close()` are the only sanctioned transitions.
- `BoringViewCoordinator.shared` — cross-window UI state: current tab (`NotchViews`), sneak peeks, expanded items, selected screen. It is also the single subscriber of `NotchUIEventBus`.
- Singleton managers (`MusicManager`, `BatteryActivityManager`, `BrightnessManager`, `VolumeManager`, `WebcamManager`, `CalendarManager`, `SystemNotificationManager`, `ShelfStateViewModel`) — each `.shared`, published into views directly.

**Presentation events.** `models/NotchUIEvent.swift` defines `NotchUIEvent` + `NotchUIEventBus` (a `PassthroughSubject`). Managers emit sneak-peek/expand events onto the bus; the coordinator subscribes and applies presentation policy (`Defaults[.osdReplacement]` etc.). This inversion exists because the coordinator also *configures* those managers — direct calls back created a cycle.

**Settings.** Persisted settings are `Defaults` keys declared in one place: `extension Defaults.Keys` in `models/Constants.swift`. Renames need a migration plus a case in `PreferenceCompatibilityTests`. Sizing constants and notch geometry live in `sizing/matters.swift` (`getClosedNotchSize` handles real-notch vs. menu-bar-height displays).

**Media.** `MediaControllerProtocol` abstracts playback; `MusicManager` picks one implementation from `Defaults[.mediaController]` and re-subscribes on the `mediaControllerChanged` notification. `NowPlayingController` is the default and works by spawning `/usr/bin/perl mediaremote-adapter.pl <framework> stream` (bundled `mediaremote-adapter/`) and decoding the JSON lines — the workaround for macOS 15.4+ locking down MediaRemote; `helpers/MediaChecker.swift` detects when that path is dead. Apple Music/Spotify controllers drive apps via AppleScript (temporary-exception entitlements). YouTube Music talks to a companion app over HTTP.

**Privileged work goes through XPC.** The sandboxed app cannot read accessibility authorization, touch CoreBrightness, drive AX on other apps, or send Messages, so `BoringNotchXPCHelper` vends all of it: accessibility grants, keyboard/screen brightness, the Lunar event stream, Notification Center banner watching (`NotificationWatcher`, AX-based) and banner actions/replies (`MessagesSender`). Always call through `XPCHelperClient.shared`. The protocol (`Shared/BoringNotchXPCHelperProtocol.swift`) and `Shared/JSONLinesPipeHandler.swift` live in the **`Shared` synchronized group compiled into both targets — one copy, edit once**. The helper pushes banners/Lunar events back through a single `exportedObject` conforming to `BoringNotchXPCAppDelegate`. HUD replacement (`observers/MediaKeyInterceptor`) needs the accessibility grant from the helper before installing its `CGEvent` tap.

**Notifications.** `SystemNotificationManager` models only what is currently on screen — a banner token is valid while the banner is visible, so replying/acting must happen live. Reply routing per app lives with `ReplyRoutingTests` as its guard. `SmartReplyManager` drafts replies with on-device FoundationModels: macOS 26+ only, and **every reference must sit behind `@available`/`#available`** — weak-linking depends on it, and an unguarded reference can break launch on macOS 14.

**Shelf** (`components/Shelf/`) is the one part with a real MVVM split — Models/Services/ViewModels/Views. Dropped files persist as security-scoped bookmarks (`ShelfPersistenceService`, `extensions/URL+SecurityScoped.swift`); the sandbox is not negotiable, so anything touching a user file must resolve a bookmark.

## Localization

All strings live in `boringNotch/Localizable.xcstrings`. Translations are Crowdin-managed — never hand-edit non-English entries; new English strings sync out of `dev` automatically and come back as a Crowdin PR.
