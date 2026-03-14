# MicGuard

A vibe-coded, fully native macOS menu bar app that prevents the operating system and applications from hijacking your audio device selection or volume levels. Built with Swift and CoreAudio — no external dependencies, no network access, no data collection.

## The Problem

- **AirPods Hijack** — macOS switches to AirPods mic on connect, dropping Bluetooth audio quality to low-quality telephony codec
- **Volume Drift** — Conferencing apps (Meet, Teams, Zoom) use Auto-Gain Control that causes clipping and inconsistent levels
- **HDMI Hijack** — Connecting an external monitor switches audio output to its built-in speakers

## Features

- Input/output device lock
- Volume lock and smart post-meeting reset
- Auto-switch output when preferred device connects
- ON AIR indicator when mic is active

## Building

```bash
swift build
swift test
```

Or open `MicGuard.xcodeproj` in Xcode (Cmd+R).

## Privacy

All data stays local. No network connections, no analytics, no microphone access.

## License

CC BY-NC 4.0 — Free to use, modify, and share. Commercial use is not permitted. See [LICENSE](LICENSE).
