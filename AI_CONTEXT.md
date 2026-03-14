# AI Context for MicGuard

This file provides context for AI assistants working on this codebase. If you're using Claude Code, Cursor, Copilot, or similar tools — this is for you.

## Overview

Native macOS menu bar app (Swift/AppKit, CoreAudio). Prevents OS and apps from hijacking audio device selection or volume levels. Zero external dependencies.

**Build:** `swift build` | **Test:** `swift test` | **Run:** Xcode Cmd+R

## Architecture

Layered component architecture with dependency injection and Combine-based reactive communication.

**Initialization order** (AppDelegate.applicationDidFinishLaunching):
1. `AudioDeviceManager` — CoreAudio wrapper (device enumeration, volume control, listener registration)
2. `DeviceWatchdog` / `OutputDeviceWatchdog` — enforces preferred device via priority-ordered list
3. `VolumeGuard` — enforces target volume using CoreAudio property listeners
4. `ActivityMonitor` — detects mic-in-use state via CoreAudio running state + polling fallback
5. `StatusBarController` — menu bar UI, receives all above as dependencies

**Source layout:**
- `MicGuard/App/` — Entry point and lifecycle (AppDelegate coordinates everything)
- `MicGuard/Core/` — AudioDeviceManager, DeviceWatchdog, VolumeGuard, ActivityMonitor, ProcessMonitor
- `MicGuard/UI/` — StatusBarController, DeviceSubmenuBuilder, OutputDeviceSubmenuBuilder, MenuItemFactory, OnAirIndicator, OnAirSnoozeManager
- `MicGuard/Utilities/` — PreferencesManager, StatsManager, NotificationManager
- `MicGuardTests/Mocks/` — MockAudioDeviceManager for protocol-based testing

## Data Flows

**Device hijack prevention:** User sets device priority → DeviceWatchdog subscribes to `defaultInputChangedPublisher` → CoreAudio fires on device change → Watchdog checks against priority list → calls `setDefaultInputDevice()` → fires `onDeviceHijackBlocked` callback → stats increment + UI flash.

**Volume lock:** VolumeGuard attaches CoreAudio listener to device volume property → detects drift beyond tolerance (0.01) → debounces (2.5s) → corrects volume → anti-fight throttle (max 10 corrections per 5s window).

**Smart reset:** ActivityMonitor checks `isDeviceRunning` (device-level, not per-app) → when mic stops → `onMeetingEnded` fires → if strategy is `resetWhenMicStops` and current volume < target → resets volume.

**Preference propagation:** UI change → PreferencesManager writes UserDefaults + publishes key via Combine → AppDelegate dispatches to appropriate guard component.

## Where to Add New Code

**New enforcement feature:** Add to `MicGuard/Core/`. Create protocol for testability. Inject AudioDeviceManager. Wire callbacks in AppDelegate. Register cleanup in `applicationWillTerminate`.

**New UI control:** Add to `StatusBarController.setupMenu()`. Frame-based NSView layout (not Auto Layout). Tag arithmetic for label/slider association (tag + 1000). Commit slider values on mouseUp only, not continuous drag.

**New preference:** Add key to PreferencesManager (getter/setter + UserDefaults + publish key). Add to protocol. Handle in AppDelegate's `handlePreferenceChange(key:)`.

**New test:** Add `{Component}Tests.swift` in MicGuardTests. Use MockAudioDeviceManager for deterministic testing.

## Known Limitations

**"Reset When Mic Not In Use" misses overlapping app usage:** `isDeviceRunning` is device-level — if Discord holds the mic while you leave a Zoom call, the device stays "running" and the volume reset never triggers. Users in persistent voice calls should use "Lock Input Volume" instead.

**Notifications disabled:** Commented out in AppDelegate due to bundle identifier crash when running outside Xcode.

**StatusBarController is large (~800 lines):** Menu building, state management, and event subscriptions in one file. Some extraction done (OnAirIndicator, OnAirSnoozeManager, DeviceSubmenuBuilder) but more could be split out.

**CoreAudio listener lifecycle is fragile:** Listeners registered per-device can fail silently if device ID becomes invalid between registration and removal. Always check removal status.

**ProcessMonitor uses hardcoded bundle IDs:** New audio apps won't be detected until bundle IDs are added. Falls back to `.nonRTC` for unknown apps.

**No anti-fight test coverage:** VolumeGuard throttle mechanism works but has no unit tests.

## Conventions

- Protocols: `AudioDeviceManaging`, `DeviceWatchdogProtocol`, `PreferencesManaging`
- Callbacks: closure-based (`onDeviceHijackBlocked`, `onVolumeCorrected`, `onMeetingEnded`)
- Reactive: Combine PassthroughSubject publishers for cross-component communication
- Logging: `print()` with emoji prefixes (no logging framework)
- Volume values: Float 0.0–1.0, clamped via `max(0, min(1, value))`
- Package.swift explicitly lists all source files — update it when adding new files
