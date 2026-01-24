//
//  ProcessMonitor.swift
//  MicGuard
//
//  Detects which process/application is using audio devices
//

import Foundation
import AppKit

// MARK: - Mic Usage Type

enum MicUsageType: Equatable {
    case webrtc
    case nonRTC
    case none
}

// MARK: - Protocol for Testability

protocol ProcessMonitoring {
    func detectActiveAudioProcessType() -> MicUsageType
    func isBrowserProcess(_ bundleId: String) -> Bool
}

// MARK: - ProcessMonitor Implementation

class ProcessMonitor: ProcessMonitoring {
    
    // MARK: - Known Browser Bundle IDs
    
    private let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.Safari.Technology.Preview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "com.brave.Browser",
        "com.brave.Browser.dev",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "com.chromium.Chromium",
        "company.thebrowser.Browser" // Arc browser
    ]
    
    // MARK: - Public Methods
    
    /// Detects what type of process is using the microphone
    /// Returns .webrtc if a browser is using it, .nonRTC if a native app, .none if unknown
    func detectActiveAudioProcessType() -> MicUsageType {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        // Strategy: Check if known audio apps are running
        // Priority: Known audio apps > Browsers
        // This way Discord/Zoom takes precedence over Chrome being open
        
        let activeApps = runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            
            // Skip system processes and our own app
            if bundleId.hasPrefix("com.apple.") && bundleId != "com.apple.Safari" && bundleId != "com.apple.FaceTime" {
                return false
            }
            if bundleId.contains("MicGuard") {
                return false
            }
            
            // App should be running (not necessarily focused)
            return !app.isTerminated
        }
        
        var hasBrowser = false
        var hasNativeApp = false

        for app in activeApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            if isBrowserProcess(bundleId) {
                hasBrowser = true
            } else if isKnownAudioApp(bundleId) {
                hasNativeApp = true
            }
        }

        if hasNativeApp {
            return .nonRTC
        } else if hasBrowser {
            return .webrtc
        }

        return .nonRTC
    }
    
    /// Check if a bundle ID belongs to a browser
    func isBrowserProcess(_ bundleId: String) -> Bool {
        return browserBundleIds.contains(bundleId)
    }
    
    // MARK: - Internal Methods

    func isKnownAudioApp(_ bundleId: String) -> Bool {
        let knownAudioApps = [
            "com.discord",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap", // Slack
            "com.skype.skype",
            "com.cisco.webexmeetings",
            "com.apple.FaceTime",
            "com.teamviewer.TeamViewer",
            "com.reincubate.camo", // Camo
            "com.obsproject.obs-studio", // OBS
            "com.rogueamoeba.AudioHijackPro",
            "com.shinywhitebox.ishowu-instant",
            "com.ecamm.EcammLive",
            "us.loom.desktop", // Loom
        ]
        
        return knownAudioApps.contains(bundleId)
    }
}
