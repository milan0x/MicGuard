//
//  MicGuardApp.swift
//  MicGuard
//
//  Your Mic, Your Rules.
//

import SwiftUI

@main
struct MicGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
