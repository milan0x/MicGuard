# Known Issues

**"Reset When Mic Not In Use" misses overlapping apps**
`isDeviceRunning` is device-level — if Discord holds the mic while you leave a Zoom call, the device stays "running" and the reset never fires. Use "Lock Input Volume" instead if you're in persistent voice calls.

**Notifications are disabled**
The `NotificationManager` class exists but isn't wired up. Running outside Xcode caused a bundle ID crash, so it's been left dormant.

**ProcessMonitor uses hardcoded bundle IDs**
New audio apps aren't detected until added. Unknown apps fall back to `.nonRTC`.

**Device name-based matching is ambiguous**
When a device reconnects with a new UID, matching falls back to name. If two devices share the same name, the match is arbitrary.

**CoreAudio listener lifecycle is fragile**
Per-device listeners can fail silently if a device ID becomes invalid between registration and removal. Rapid hot-plug scenarios are not well tested.

**VolumeGuard debounce and anti-fight can interact**
The 2.5s debounce and 10-corrections-per-5s throttle can combine in unexpected ways when an app is aggressively fighting the volume lock.

**StatusBarController is large**
~800 lines handling menu building, state, and event subscriptions. Some extraction has happened but it's still a big file.

**Test coverage gaps**
VolumeGuard anti-fight throttling, DeviceWatchdog duplicate-name fallback, CoreAudio listener lifecycle, and snooze timer edge cases have no test coverage.
