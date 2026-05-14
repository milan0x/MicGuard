# CLAUDE.md

See [AI_CONTEXT.md](AI_CONTEXT.md) for full project context, architecture, data flows, and contribution guide.

## Quick Reference

```bash
swift build          # Build via SPM
swift test           # Run all tests
```

- Package.swift explicitly lists all source files — update it when adding new files
- Slider values: update label on drag, commit to PreferencesManager only on mouseUp
- CoreAudio listener cleanup in `applicationWillTerminate` is critical — AudioDeviceManager is set to nil
- Notifications are disabled (bundle identifier crash outside Xcode)
