//
//  PreferencesManager.swift
//  MicGuard
//
//  Manages app preferences using UserDefaults
//

import Foundation
import Combine

// MARK: - Volume Control Strategy

enum VolumeControlStrategy: String, CaseIterable {
    case none
    case lockVolume
    case resetWhenMicStops
    
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .lockVolume:
            return "Lock Input Volume (Continuous Protection)"
        case .resetWhenMicStops:
            return "Reset When Mic Stops"
        }
    }
}

// MARK: - Protocol for Testability

protocol PreferencesManaging {
    // Input Device Preferences
    var preferredInputDeviceUID: String? { get set }
    var preferredInputDeviceOrder: [String] { get set }
    var inputDeviceLockEnabled: Bool { get set }

    // Output Device Preferences
    var preferredOutputDeviceUID: String? { get set }
    var preferredOutputDeviceOrder: [String] { get set }
    var outputDeviceLockEnabled: Bool { get set }
    var outputAutoSwitchEnabled: Bool { get set }

    // Volume Preferences
    var volumeControlStrategy: VolumeControlStrategy { get set }
    var targetVolume: Float { get set }

    // App Settings
    var launchAtLogin: Bool { get set }
    var showInMenuBar: Bool { get set }
    var showNotifications: Bool { get set }
    var showOnAirIndicator: Bool { get set }
    var onAirSnoozeUntil: Date? { get set }
    var isOnAirSnoozed: Bool { get }
    var showStats: Bool { get set }

    // Input device order management
    func moveDevice(uid: String, direction: MoveDirection)
    func addDeviceToOrder(_ uid: String)
    func removeDeviceFromOrder(_ uid: String)

    // Output device order management
    func moveOutputDevice(uid: String, direction: MoveDirection)
    func addOutputDeviceToOrder(_ uid: String)
    func removeOutputDeviceFromOrder(_ uid: String)

    // Device name cache (for showing names when disconnected)
    func cacheDeviceName(uid: String, name: String)
    func cachedDeviceName(for uid: String) -> String?

    // UID migration (for name-based device matching after reconnection)
    func replaceDeviceUID(oldUID: String, newUID: String)
    func replaceOutputDeviceUID(oldUID: String, newUID: String)

    // Observable changes
    var preferencesChangedPublisher: PassthroughSubject<String, Never> { get }
}

// MARK: - UserDefaults Keys

private enum PreferenceKey: String {
    // Input Device Preferences
    case preferredInputDeviceUID = "PreferredInputDeviceUID"
    case preferredInputDeviceOrder = "PreferredInputDeviceOrder"
    case inputDeviceLockEnabled = "InputDeviceLockEnabled"

    // Output Device Preferences
    case preferredOutputDeviceUID = "PreferredOutputDeviceUID"
    case preferredOutputDeviceOrder = "PreferredOutputDeviceOrder"
    case outputDeviceLockEnabled = "OutputDeviceLockEnabled"
    case outputAutoSwitchEnabled = "OutputAutoSwitchEnabled"
    
    // Volume Preferences
    case volumeControlStrategy = "VolumeControlStrategy"
    case targetVolume = "TargetVolume"
    
    // Device Name Cache
    case deviceNameCache = "DeviceNameCache"

    // App Settings
    case launchAtLogin = "LaunchAtLogin"
    case showInMenuBar = "ShowInMenuBar"
    case showNotifications = "ShowNotifications"
    case showOnAirIndicator = "ShowOnAirIndicator"
    case onAirSnoozeUntil = "OnAirSnoozeUntil"
    case showStats = "ShowStats"
}

// MARK: - PreferencesManager Implementation

class PreferencesManager: PreferencesManaging {
    
    // MARK: - Singleton
    
    static let shared = PreferencesManager()
    
    // MARK: - Properties
    
    private let defaults: UserDefaults
    let preferencesChangedPublisher = PassthroughSubject<String, Never>()
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        migrateOldPreferences()
    }
    
    private func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.inputDeviceLockEnabled.rawValue: false,
            PreferenceKey.outputDeviceLockEnabled.rawValue: false,
            PreferenceKey.outputAutoSwitchEnabled.rawValue: false,
            PreferenceKey.volumeControlStrategy.rawValue: VolumeControlStrategy.resetWhenMicStops.rawValue,
            PreferenceKey.targetVolume.rawValue: Float(0.75),
            PreferenceKey.launchAtLogin.rawValue: false,
            PreferenceKey.showInMenuBar.rawValue: true,
            PreferenceKey.showNotifications.rawValue: true,
            PreferenceKey.showOnAirIndicator.rawValue: true,
            PreferenceKey.showStats.rawValue: false
        ])
    }
    
    // MARK: - Device Preferences
    
    var preferredInputDeviceUID: String? {
        get { defaults.string(forKey: PreferenceKey.preferredInputDeviceUID.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.preferredInputDeviceUID.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.preferredInputDeviceUID.rawValue)
        }
    }
    
    var inputDeviceLockEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKey.inputDeviceLockEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.inputDeviceLockEnabled.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.inputDeviceLockEnabled.rawValue)
        }
    }
    
    var preferredInputDeviceOrder: [String] {
        get {
            defaults.array(forKey: PreferenceKey.preferredInputDeviceOrder.rawValue) as? [String] ?? []
        }
        set {
            // Deduplicate while preserving order
            var seen = Set<String>()
            let unique = newValue.filter { seen.insert($0).inserted }
            
            defaults.set(unique, forKey: PreferenceKey.preferredInputDeviceOrder.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.preferredInputDeviceOrder.rawValue)
        }
    }
    
    // MARK: - Output Device Preferences

    var preferredOutputDeviceUID: String? {
        get { defaults.string(forKey: PreferenceKey.preferredOutputDeviceUID.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.preferredOutputDeviceUID.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.preferredOutputDeviceUID.rawValue)
        }
    }

    var outputDeviceLockEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKey.outputDeviceLockEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.outputDeviceLockEnabled.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.outputDeviceLockEnabled.rawValue)
        }
    }

    var preferredOutputDeviceOrder: [String] {
        get {
            defaults.array(forKey: PreferenceKey.preferredOutputDeviceOrder.rawValue) as? [String] ?? []
        }
        set {
            var seen = Set<String>()
            let unique = newValue.filter { seen.insert($0).inserted }
            defaults.set(unique, forKey: PreferenceKey.preferredOutputDeviceOrder.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.preferredOutputDeviceOrder.rawValue)
        }
    }

    var outputAutoSwitchEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKey.outputAutoSwitchEnabled.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.outputAutoSwitchEnabled.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.outputAutoSwitchEnabled.rawValue)
        }
    }

    // MARK: - Volume Preferences
    
    var volumeControlStrategy: VolumeControlStrategy {
        get {
            guard let rawValue = defaults.string(forKey: PreferenceKey.volumeControlStrategy.rawValue),
                  let strategy = VolumeControlStrategy(rawValue: rawValue) else {
                return .none
            }
            return strategy
        }
        set {
            defaults.set(newValue.rawValue, forKey: PreferenceKey.volumeControlStrategy.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.volumeControlStrategy.rawValue)
        }
    }
    
    var targetVolume: Float {
        get { defaults.float(forKey: PreferenceKey.targetVolume.rawValue) }
        set {
            let clamped = max(0, min(1, newValue))
            defaults.set(clamped, forKey: PreferenceKey.targetVolume.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.targetVolume.rawValue)
        }
    }
    
    // MARK: - App Settings
    
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: PreferenceKey.launchAtLogin.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.launchAtLogin.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.launchAtLogin.rawValue)
            
            // Actually register/unregister with the system
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
        }
    }
    
    var showInMenuBar: Bool {
        get { defaults.bool(forKey: PreferenceKey.showInMenuBar.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.showInMenuBar.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.showInMenuBar.rawValue)
        }
    }
    
    var showNotifications: Bool {
        get { defaults.bool(forKey: PreferenceKey.showNotifications.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.showNotifications.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.showNotifications.rawValue)
        }
    }
    
    var showOnAirIndicator: Bool {
        get { defaults.bool(forKey: PreferenceKey.showOnAirIndicator.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.showOnAirIndicator.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.showOnAirIndicator.rawValue)
        }
    }

    var onAirSnoozeUntil: Date? {
        get {
            let interval = defaults.double(forKey: PreferenceKey.onAirSnoozeUntil.rawValue)
            guard interval > 0 else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: PreferenceKey.onAirSnoozeUntil.rawValue)
            } else {
                defaults.removeObject(forKey: PreferenceKey.onAirSnoozeUntil.rawValue)
            }
            preferencesChangedPublisher.send(PreferenceKey.onAirSnoozeUntil.rawValue)
        }
    }

    var isOnAirSnoozed: Bool {
        guard let snoozeEnd = onAirSnoozeUntil else { return false }
        return snoozeEnd > Date()
    }

    var showStats: Bool {
        get { defaults.bool(forKey: PreferenceKey.showStats.rawValue) }
        set {
            defaults.set(newValue, forKey: PreferenceKey.showStats.rawValue)
            preferencesChangedPublisher.send(PreferenceKey.showStats.rawValue)
        }
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.micguard.app"
        defaults.removePersistentDomain(forName: domain)
        registerDefaults()
    }
    
    // MARK: - Migration
    
    private func migrateOldPreferences() {
        // Migrate single preferredInputDeviceUID to array if needed
        if preferredInputDeviceOrder.isEmpty,
           let oldUID = preferredInputDeviceUID {
            preferredInputDeviceOrder = [oldUID]
        }
        
        // Migrate old volume control preferences to new strategy
        let oldLockEnabledKey = "InputVolumeLockEnabled"
        let oldAutoResetKey = "AutoResetEnabled"
        let oldLockedVolumeKey = "LockedInputVolume"
        let oldResetVolumeKey = "DefaultResetVolume"
        
        // Only migrate if new strategy is not set
        if defaults.string(forKey: PreferenceKey.volumeControlStrategy.rawValue) == nil {
            let oldLockEnabled = defaults.bool(forKey: oldLockEnabledKey)
            let oldAutoResetEnabled = defaults.bool(forKey: oldAutoResetKey)
            
            // Determine new strategy based on old settings
            if oldLockEnabled {
                volumeControlStrategy = .lockVolume
                // Migrate target volume from old locked volume
                if let oldVolume = defaults.object(forKey: oldLockedVolumeKey) as? Float {
                    targetVolume = oldVolume
                }
            } else if oldAutoResetEnabled {
                volumeControlStrategy = .resetWhenMicStops
                // Migrate target volume from old reset volume
                if let oldVolume = defaults.object(forKey: oldResetVolumeKey) as? Float {
                    targetVolume = oldVolume
                }
            } else {
                volumeControlStrategy = .none
            }
            
            // Clean up old keys
            defaults.removeObject(forKey: oldLockEnabledKey)
            defaults.removeObject(forKey: oldAutoResetKey)
            defaults.removeObject(forKey: oldLockedVolumeKey)
            defaults.removeObject(forKey: oldResetVolumeKey)
        }
    }
    
    // MARK: - Device Order Management
    
    func moveDevice(uid: String, direction: MoveDirection) {
        var order = preferredInputDeviceOrder
        guard let currentIndex = order.firstIndex(of: uid) else { return }
        
        switch direction {
        case .up:
            guard currentIndex > 0 else { return }
            order.swapAt(currentIndex, currentIndex - 1)
        case .down:
            guard currentIndex < order.count - 1 else { return }
            order.swapAt(currentIndex, currentIndex + 1)
        case .toTop:
            order.remove(at: currentIndex)
            order.insert(uid, at: 0)
        }
        
        preferredInputDeviceOrder = order
    }
    
    func addDeviceToOrder(_ uid: String) {
        var order = preferredInputDeviceOrder
        guard !order.contains(uid) else { return }
        order.append(uid)
        preferredInputDeviceOrder = order
    }
    
    func removeDeviceFromOrder(_ uid: String) {
        var order = preferredInputDeviceOrder
        order.removeAll { $0 == uid }
        preferredInputDeviceOrder = order
    }

    // MARK: - Output Device Order Management

    func moveOutputDevice(uid: String, direction: MoveDirection) {
        var order = preferredOutputDeviceOrder
        guard let currentIndex = order.firstIndex(of: uid) else { return }

        switch direction {
        case .up:
            guard currentIndex > 0 else { return }
            order.swapAt(currentIndex, currentIndex - 1)
        case .down:
            guard currentIndex < order.count - 1 else { return }
            order.swapAt(currentIndex, currentIndex + 1)
        case .toTop:
            order.remove(at: currentIndex)
            order.insert(uid, at: 0)
        }

        preferredOutputDeviceOrder = order
    }

    func addOutputDeviceToOrder(_ uid: String) {
        var order = preferredOutputDeviceOrder
        guard !order.contains(uid) else { return }
        order.append(uid)
        preferredOutputDeviceOrder = order
    }

    func removeOutputDeviceFromOrder(_ uid: String) {
        var order = preferredOutputDeviceOrder
        order.removeAll { $0 == uid }
        preferredOutputDeviceOrder = order
    }

    // MARK: - Device Name Cache

    func cacheDeviceName(uid: String, name: String) {
        var cache = defaults.dictionary(forKey: PreferenceKey.deviceNameCache.rawValue) as? [String: String] ?? [:]
        cache[uid] = name
        defaults.set(cache, forKey: PreferenceKey.deviceNameCache.rawValue)
    }

    func cachedDeviceName(for uid: String) -> String? {
        let cache = defaults.dictionary(forKey: PreferenceKey.deviceNameCache.rawValue) as? [String: String]
        return cache?[uid]
    }

    // MARK: - UID Migration

    func replaceDeviceUID(oldUID: String, newUID: String) {
        // Update priority order
        var order = preferredInputDeviceOrder
        if let index = order.firstIndex(of: oldUID) {
            order[index] = newUID
            preferredInputDeviceOrder = order
        }

        // Migrate cached name to new UID
        if let name = cachedDeviceName(for: oldUID) {
            cacheDeviceName(uid: newUID, name: name)
        }

        // Update preferredInputDeviceUID if it was the old one
        if preferredInputDeviceUID == oldUID {
            preferredInputDeviceUID = newUID
        }
    }

    func replaceOutputDeviceUID(oldUID: String, newUID: String) {
        var order = preferredOutputDeviceOrder
        if let index = order.firstIndex(of: oldUID) {
            order[index] = newUID
            preferredOutputDeviceOrder = order
        }

        if let name = cachedDeviceName(for: oldUID) {
            cacheDeviceName(uid: newUID, name: name)
        }

        if preferredOutputDeviceUID == oldUID {
            preferredOutputDeviceUID = newUID
        }
    }
}

// MARK: - Move Direction

enum MoveDirection {
    case up
    case down
    case toTop
}

// MARK: - Launch at Login Manager

import ServiceManagement

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    
    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Launch at login registration failed
            }
        } else {
            // Fallback for older macOS versions
        }
    }
    
    @available(macOS 13.0, *)
    var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
}
