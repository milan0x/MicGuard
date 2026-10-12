# MicGuard Audit — open items

Code + UX review, first done 2026-06-12 and re-verified against the code on
2026-10-11 (v1.4). Fixed items are removed; everything below was confirmed
still present. Items in AI_CONTEXT.md "Known Limitations" or TODO.md are not
repeated here.

## Correctness

- [ ] **VolumeGuard's anti-fight throttle is unreachable.**
  (`Core/VolumeGuard.swift`.) Corrections are counted only when a debounced
  work item fires; with a 2.5s deadline-capped debounce in a 5s window the
  counter tops out around 2, the threshold is 10, so `onThrottleStateChanged`
  can never fire. Harmless today (the deadline cap already prevents starvation)
  but the throttle and its callbacks are dead code. Either size the threshold
  to what the debounce permits, or delete the mechanism.

- [ ] **`isSettingVolume` self-event suppression is a no-op.**
  (`Core/VolumeGuard.swift`.) Set/cleared synchronously around a listener that
  fires asynchronously, so it is always false by the time the guard runs.
  Masked by the drift-tolerance check. Delete the flag or use a deadline
  (`suppressEventsUntil`).

- [ ] **Stale device-cache window on unplug.** (`Core/AudioDeviceManager.swift`,
  `Core/DeviceWatchdog.swift`.) Default-change listeners resolve against the
  cached device list; CoreAudio does not order default-changed vs
  devices-changed notifications, so enforcement can briefly run against a list
  that still contains the unplugged device. The watchdog's nil-default
  re-check and stick-failure verification contain the damage; a
  `refreshDeviceList()` at the top of the default-change listener blocks would
  remove it.

- [ ] **UID re-matching does not migrate per-device custom volumes.**
  (`Utilities/PreferencesManager.swift`.) `replaceOutputDeviceUID` migrates
  priority order, cached name, preferred UID and exclusion, but not
  `OutputDeviceVolumes`, so set-on-activation silently stops working for
  devices that re-enumerate with a new UID (AirPods, USB). Fix: move
  `dict[oldUID]` → `dict[newUID]`.

- [ ] **`applicationWillTerminate` comment is wrong.** (`App/AppDelegate.swift`,
  also repeated in CLAUDE.md.) Setting `audioDeviceManager = nil` cannot force
  listener cleanup — five other strong references keep the manager alive. The
  manager's own `willTerminate` observer does the real work. Fix the comment
  before someone deletes that observer.

- [ ] **Ignored `OSStatus` from `AudioObjectAddPropertyListenerBlock`.**
  (`Core/AudioDeviceManager.swift`.) A failed registration silently degrades
  event-driven detection to the 2s poll. Log it.

- [ ] **`startWatching` while already watching skips `enforcePreferredDevice()`**
  unlike `updateDevicePriorityOrder`. Masked by AppDelegate's stop-first and
  update-in-place patterns.

## Dead code (delete candidates)

- [ ] `ProcessMonitor` + `micUsageTypePublisher`: computed on every poll, zero
  subscribers. Presence-based attribution was never good enough to show anyway.
- [ ] `NotificationManager` + `showNotifications` preference: no callers, no UI.
- [ ] `showInMenuBar` preference: registered and tested, read nowhere.
- [ ] `.inputDeviceLockChanged` / `.outputDeviceLockChanged`: posted, zero observers.
- [ ] `.inputVolumeLockChanged` / `.autoResetChanged` / `.lockedVolumeChanged`:
  declared, never posted.
- [ ] `resetToDefaults()`: never called (and would not refresh the UI or
  unregister the login item if it were).
- [ ] `@State showSnoozeMenu` in `SettingsSection`: unused stub of an
  abandoned snooze feature.
- [ ] `cacheDeviceName` rewrites the whole dictionary on every device-change
  event even when nothing changed. Skip when unchanged.

## Tests

- [ ] Tautological tests that only invoke the closure they just assigned:
  `testMeetingStartedCallback`, `testMeetingEndedCallback`,
  `testOnVolumeCorrectedCallback`, `testThrottleCallbackSetup`,
  `testShouldNotThrottleUnderLimit`. Delete or make them drive real paths
  (`ActivityMonitorTests.testMeetingEndsWhenDeviceStopsRunning` shows how).
- [ ] Sustained volume fight engaging the throttle is untested (and cannot
  pass today, see above).
- [ ] `MockAudioDeviceManager.setDefaultInputDevice` publishes synchronously
  and always succeeds unless listed in `silentlyRefusedUIDs`; the real HAL is
  async and can re-override, so fight loops are structurally invisible.

## UX

- [ ] **Icon does not show yielded state.** Master pause has its own slashed
  icon, but a lock that the user yielded (not enforcing) looks identical to an
  armed one in the menu bar. `onYielded` already exists; add a distinct glyph.
- [ ] About dialog does not activate the app before `NSAlert.runModal()`, so
  in an `LSUIElement` app the alert can open behind the frontmost window.
- [ ] Flash labels resize the status item — the menu bar reflows twice per
  flash and off-cycles render a blank hole (image nil + alpha-0 title).
  `pulse()` avoids this by design; flashes should meet the same bar.
- [ ] Right-click menu: "Reactivate Input/Output Lock" is enabled when nothing
  is yielded (silent no-op); menu lacks About and Launch at Login.
- [ ] No first-run moment: nothing opens on first launch while the volume
  strategy defaults to active (reset-when-mic-stops @ 75%), so MicGuard's
  first observable act can be silently changing the user's volume. One
  `popover.show()` on first launch would show the whole value proposition.
- [ ] Accessibility: chevron / xmark / slash icon buttons have `.help()` but no
  `.accessibilityLabel`; hand-rolled radio rows (`VolumeStrategyRow`,
  `MicIndicatorOption`) lack the `.isSelected` trait; the on-air pill passes
  `accessibilityDescription: nil`.
- [ ] Popover scroll area always takes its full `maxHeight: 620` — dead space on sparse tabs.
- [ ] README screenshot predates the SwiftUI popover.

## Worth building

1. **Snooze** (1h / until tomorrow). Consent-yield covers accidental fights;
   snooze covers intentional ones (screen shares, troubleshooting). Master
   pause is the indefinite version; a timed one is the missing piece.
2. **Tiny event log** — last ~10 actions with timestamps ("14:02 held input:
   AirPods → Shure MV7"). Every callback already exists. Makes invisible value
   visible.
3. **Yielded state in the icon** (above).

Not worth building: a per-app rules engine (maintenance treadmill on private
behavior); anything requiring mic permission (zero-permission is the brand);
a floating on-air overlay; richer mic attribution to one-up the system
indicator. MicGuard is an enforcer, not an indicator.
