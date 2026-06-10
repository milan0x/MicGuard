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

## Feature: Smart initial device-priority order

On first launch (and whenever a brand-new UID is appended to the priority list), `addDeviceToOrder` in `PreferencesManager.swift` appends to the tail. The first time the user opens MicGuard, the saved order is therefore whatever sequence CoreAudio happened to enumerate devices in — effectively arbitrary. The lock then snaps the system default to the top of that list (`PopoverViewModel.swift:419`), which means a user with Continuity enabled can land on their iPhone microphone the moment they install the app. Worst possible first impression.

### Proposed ranking (best → worst)

Bucket by `transportType` on insert instead of appending blindly. Order based on inferred intent:

1. **External / real microphone** — anything not in the buckets below. The strongest signal of "deliberate choice": if you plugged in a USB / XLR / HDMI / Thunderbolt mic, you meant it.
2. **MacBook built-in** (`kAudioDeviceTransportTypeBuiltIn`) — sensible default fallback when no external is connected.
3. **Bluetooth / AirPods** (`kAudioDeviceTransportTypeBluetooth`, `kAudioDeviceTransportTypeBluetoothLE`) — intentional wearable, but lower quality than a wired mic and not always present.
4. **iPhone via Continuity** (`kAudioDeviceTransportTypeContinuityCapture`, `kAudioDeviceTransportTypeContinuityCaptureWired`) — convenience feature, rarely the device the user actually wants for calls.
5. **Virtual / aggregate** (`kAudioDeviceTransportTypeVirtual`, `kAudioDeviceTransportTypeAggregate`) — already classified as `isLikelyUnsettable` in `AudioDeviceManager.swift:36`. Almost never the real mic.

The detection trick: bucket #1 ("external") is defined as "anything *not* in buckets 2–5" rather than enumerating known external transport types. That way an unknown future transport type still defaults to "treat as a real mic" rather than getting accidentally demoted.

### Scope notes

- **New devices only.** Do not re-bucket existing saved orders on upgrade — a user who has deliberately reordered must not have their list rewritten. Only newly-appended UIDs flow through the bucketing logic.
- **Optional "Reset to recommended order" button** in Settings for users who want to opt back in to the new ordering after upgrade.
- **Schema-stability note:** the priority list is the user's source of truth. Any future refactor that touches the storage shape needs a migration path that preserves it. Worth a comment at the `preferredInputDeviceOrder` / `preferredOutputDeviceOrder` declaration site so it's not forgotten.
- **Lock-enabled-on-first-launch** is a separate question. Could ship lock off until the user confirms, even after the smart-seed lands. Decide closer to implementation.
- **Both inputs and outputs.** Same logic applies to `preferredOutputDeviceOrder` — AirPods-vs-built-in-speakers has the same "what did the user actually mean" problem.
