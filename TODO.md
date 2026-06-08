# TODO

## Feature: Fall through to next priority device when preferred device is unusable

When the preferred input/output device is enumerated but not actually usable, the watchdog should fall through to the next available device in the priority list instead of trying to enforce the unreachable device.

The motivating case is **clamshell mode**: when the MacBook lid is closed (with an external display attached), the built-in microphone is physically disabled but typically remains present in CoreAudio's device list, still reporting alive and running. The watchdog currently has no signal that the device is unusable.

### Open question — detection signal

It is unclear whether CoreAudio exposes any property that flips for the built-in mic when the lid closes. Likely candidates that probably do **not** work:

- `kAudioDevicePropertyDeviceIsAlive` — hardware stays powered (T2 manages privacy), expected to remain `true`
- `kAudioDevicePropertyDeviceIsRunning` — same reasoning

If the empirical test confirms CoreAudio gives no usable signal, fallback options:

1. **IOKit clamshell notification** — `IOServiceAddInterestNotification` on `AppleClamshellState`. Reliable for the lid case specifically, but adds an IOKit dependency and only covers this one scenario.
2. **Generalized "device unreachable" heuristic** — sustained absence of input signal, failure to set as default, etc. Fragile.

Recommended first step: write a small probe that logs CoreAudio device properties before and after a lid close on a real machine, then decide the detection path from data.

### Scope notes

- Generalizes beyond lid close: USB hub sleep, AirPods out of range, dock disconnects without device removal.
- Should compose cleanly with the existing auto-yield mechanism (`AutoYieldOnRepeatedOverride`) — fallthrough is system-initiated, not user-initiated, so it should not count toward the yield threshold.
- UX: probably automatic with no new preference. The priority list already encodes the user's fallback intent.
