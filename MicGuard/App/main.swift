//
//  main.swift
//  MicGuard
//
//  Your Mic, Your Rules.
//
//  Plain AppKit entry point. The app is a status item + popover owned by
//  AppDelegate; a SwiftUI `App` would force at least one scene, and the
//  placeholder `Settings { EmptyView() }` it needed surfaced as an empty
//  "MicGuard Settings" window on ⌘,.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
