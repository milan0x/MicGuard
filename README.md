# MicGuard

> Your Mic, Your Rules.

A native macOS menu bar app that prevents the operating system and applications from hijacking your audio device selection or volume levels. No external dependencies, no network access, no data collection.

## The Problem

- **AirPods Hijack** — When AirPods connect, macOS switches to their microphone, dropping Bluetooth audio quality from high-fidelity A2DP to low-quality telephony codec.
- **Volume Drift** — Web conferencing apps (Google Meet, Teams, Zoom) use Auto-Gain Control that causes clipping and inconsistent audio levels.
- **HDMI Hijack** — Connecting an external monitor via HDMI/DisplayPort causes macOS to switch audio output to the monitor's built-in speakers.

## Features

- **Input Device Lock** — Keep your preferred microphone selected, always
- **Output Device Lock** — Prevent macOS from switching your speakers/headphones
- **Volume Lock** — Prevent apps from adjusting your mic gain
- **Smart Reset** — Automatically restore volume levels after meetings end
- **Auto-Switch on Connect** — Automatically switch to your preferred output device when it appears
- **ON AIR Indicator** — Visual indicator in the menu bar when your mic is active
- **Stats** — Track how many times MicGuard saved your settings

## Requirements

- macOS 13.0 (Ventura) or later

## Building

Open `MicGuard.xcodeproj` in Xcode and build (Cmd+R), or:

```bash
swift build
swift test
```

## Privacy

- All data is stored locally in UserDefaults
- No cloud sync, no analytics, no telemetry
- No network connections
- No microphone access or recording

## A Note on How This Was Built

This app was vibe-coded — built iteratively through conversation with AI assistants. The architecture, implementation, and tests were developed collaboratively between a human and AI. It works, it solves a real problem, and the code is here for you to read and judge for yourself.

## License

CC BY-NC 4.0 — Free to use, modify, and share. Commercial use is not permitted. See [LICENSE](LICENSE) for details.
