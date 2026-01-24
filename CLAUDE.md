# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MicGuard is a native macOS menu bar app (Swift/AppKit/SwiftUI) that prevents the OS and apps from hijacking microphone device selection or volume levels. It uses CoreAudio listener blocks for event-driven monitoring. No external dependencies.

**Requirements:** macOS 13.0+, Swift 5.9+

## Build & Test Commands

```bash
swift build          # Build via SPM
swift test           # Run all tests
```

Alternatively, open `MicGuard.xcodeproj` in Xcode and build/run with Cmd+R.

## Architecture

**Layered component architecture with dependency injection and Combine-based reactive communication.**

### Startup Flow (AppDelegate)

`AppDelegate.applicationDidFinishLaunching` creates all components in order:
1. `AudioDeviceManager` - CoreAudio wrapper (device enumeration, volume control, listener registration)
2. `DeviceWatchdog` - enforces preferred input device via priority-ordered device list
3. `VolumeGuard` - enforces target volume using CoreAudio property listeners
4. `ActivityMonitor` - detects mic-in-use state by polling device running state every 2.5s
5. `StatusBarController` - menu bar UI, receives all above as dependencies

### Key Interaction Patterns

- **DeviceWatchdog** listens for default-device-changed events from AudioDeviceManager. On hijack detection, it re-sets the highest-priority available device and debounces (0.1s).
- **VolumeGuard** attaches a CoreAudio listener block to the current input device's volume property. It debounces corrections (2.5s) and has anti-fight logic (throttles after 10 corrections in 5s). Detects manual changes when System Settings is frontmost.
- **ActivityMonitor** publishes mic-in-use state and input levels via Combine publishers. `AppDelegate` uses the `onMeetingEnded` callback to trigger smart volume reset (only resets if current volume is below target).
- **PreferencesManager** (singleton) wraps UserDefaults and publishes changes via `preferencesChangedPublisher`. AppDelegate subscribes to handle strategy/device/volume preference changes.
- **Volume control has three strategies:** `none`, `lockVolume` (continuous enforcement), `resetWhenMicStops` (restore after meeting ends).

### Protocol-Based Design

All core components have protocols (`AudioDeviceManaging`, `DeviceWatchdogProtocol`, `VolumeGuardProtocol`, `ActivityMonitorProtocol`) enabling mock-based testing. Tests use `MockAudioDeviceManager` in `MicGuardTests/Mocks/`.

### Source Layout

- `MicGuard/App/` - Entry point (`MicGuardApp.swift`) and lifecycle (`AppDelegate.swift`)
- `MicGuard/Core/` - Audio engine: `AudioDeviceManager`, `DeviceWatchdog`, `VolumeGuard`, `ActivityMonitor`, `ProcessMonitor`
- `MicGuard/UI/` - `StatusBarController` (NSStatusBar + NSMenu, ~960 lines)
- `MicGuard/Utilities/` - `PreferencesManager`, `StatsManager`, `NotificationManager`

## Important Notes

- **Notifications are temporarily disabled** (commented out in AppDelegate) to avoid a bundle identifier crash when running outside Xcode.
- CoreAudio listener cleanup in `applicationWillTerminate` is critical to prevent memory leaks; the AudioDeviceManager is explicitly set to nil.
- `ProcessMonitor` identifies mic-using apps by process name to classify as WebRTC (browser) or non-RTC (Zoom, Teams, etc.).
- `StatusBarController` includes an "ON AIR" flashing indicator that activates when mic is in use and flashes on device/volume corrections.
- The `Package.swift` explicitly lists all source files rather than using directory-based discovery.
