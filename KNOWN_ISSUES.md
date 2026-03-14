# Known Issues & Limitations

## Limitations

**"Reset When Mic Not In Use" doesn't detect individual app disconnections**
The reset strategy relies on CoreAudio's device-level running state. If you leave a meeting (e.g., Zoom lowers your volume via AGC) but another app is still using the mic (e.g., Discord), MicGuard doesn't detect the meeting ended and the volume reset never triggers. Users in persistent voice calls should use "Lock Input Volume" instead.

**Notifications are disabled**
User notifications are commented out due to a bundle identifier crash when running outside Xcode. The feature is half-implemented in NotificationManager.

**ProcessMonitor uses hardcoded bundle IDs**
New audio apps won't be detected until their bundle IDs are added. Unknown apps fall back to the generic `.nonRTC` type.

## Tech Debt

**Excessive console logging**
66+ `print()` statements with emoji prefixes fire throughout the codebase, including on every 2.5s poll cycle. No debug flag or logging framework to suppress them in production.

**StatusBarController is large**
Main UI file handles menu building, state management, and event subscriptions. Some extraction has been done (OnAirIndicator, OnAirSnoozeManager, DeviceSubmenuBuilder) but more could be split out.

**OutputDeviceWatchdog duplicates DeviceWatchdog logic**
Two nearly identical classes with separate implementations. Bug fixes must be applied to both.

## Fragile Areas

**CoreAudio listener lifecycle**
Listeners registered per-device can fail silently if a device ID becomes invalid between registration and removal. Rapid device hot-plug scenarios are not well tested.

**VolumeGuard debounce + anti-fight interaction**
Both debouncing (2.5s) and anti-fight throttling (10 corrections in 5s) can interact in unexpected ways under sustained volume fighting from aggressive apps.

**Device matching by name fallback**
When a device reconnects with a new UID, name-based matching is used. If multiple devices share the same name, matching is ambiguous.

## Test Coverage Gaps

- VolumeGuard anti-fight throttling has no test coverage
- DeviceWatchdog name-based fallback matching not tested with duplicate names
- StatusBarController has minimal test coverage
- CoreAudio listener registration/removal lifecycle not tested
- Snooze timer expiry edge cases not tested
