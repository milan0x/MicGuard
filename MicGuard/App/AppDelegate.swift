//
//  AppDelegate.swift
//  MicGuard
//
//  Manages app lifecycle and coordinates core services
//

import Cocoa
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusBarController: StatusBarController?
    private var audioDeviceManager: AudioDeviceManager?
    private var deviceWatchdog: DeviceWatchdog?
    private var outputDeviceWatchdog: OutputDeviceWatchdog?
    private var volumeGuard: VolumeGuard?
    private var activityMonitor: ActivityMonitor?
    
    private let preferencesManager = PreferencesManager.shared
    private let statsManager = StatsManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[MicGuard.App] === BUILD MARKER 2026-05-15-diag1 — launching ===")
        // Initialize core audio manager
        audioDeviceManager = AudioDeviceManager()
        
        // Initialize watchdogs and guards
        setupDeviceWatchdog()
        setupOutputDeviceWatchdog()
        setupVolumeGuard()
        setupActivityMonitor()
        
        // Setup menu bar UI
        statusBarController = StatusBarController(
            audioDeviceManager: audioDeviceManager!,
            preferencesManager: preferencesManager,
            statsManager: statsManager,
            activityMonitor: activityMonitor
        )
        
        // Start monitoring if locks were previously enabled
        applyStoredPreferences()
        
        // Setup notification observers
        setupNotificationObservers()
        
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up watchdogs and guards
        deviceWatchdog?.stopWatching()
        outputDeviceWatchdog?.stopWatching()
        volumeGuard?.stopGuarding()
        activityMonitor?.stopMonitoring()
        
        // Force cleanup of CoreAudio listeners to prevent memory leaks
        // This ensures listeners are removed even on force-quit
        audioDeviceManager = nil
        
    }
    
    // MARK: - Setup Methods
    
    private func setupDeviceWatchdog() {
        guard let audioManager = audioDeviceManager else { return }
        
        deviceWatchdog = DeviceWatchdog(audioDeviceManager: audioManager)

        // Wire up name-based device matching
        deviceWatchdog?.nameForUID = { [weak self] uid in
            self?.preferencesManager.cachedDeviceName(for: uid)
        }
        deviceWatchdog?.onDeviceUIDUpdated = { [weak self] oldUID, newUID in
            self?.preferencesManager.replaceDeviceUID(oldUID: oldUID, newUID: newUID)
        }

        deviceWatchdog?.onDeviceHijackBlocked = { [weak self] _, _ in
            self?.statsManager.increment(stat: .hijacksBlocked)
            self?.statusBarController?.flashOnAirIndicator()
        }

        deviceWatchdog?.onDeviceMatchAmbiguous = { _, _ in
            // Ambiguous name match — multiple devices share the same name
        }

        deviceWatchdog?.onManualChangePaused = { [weak self] in
            self?.statusBarController?.flashOnAirIndicator()
        }

        deviceWatchdog?.onPauseResumed = { [weak self] in
            self?.statusBarController?.flashOnAirIndicator()
        }
    }
    
    private func setupOutputDeviceWatchdog() {
        guard let audioManager = audioDeviceManager else { return }

        outputDeviceWatchdog = OutputDeviceWatchdog(audioDeviceManager: audioManager)

        outputDeviceWatchdog?.nameForUID = { [weak self] uid in
            self?.preferencesManager.cachedDeviceName(for: uid)
        }
        outputDeviceWatchdog?.onDeviceUIDUpdated = { [weak self] oldUID, newUID in
            self?.preferencesManager.replaceOutputDeviceUID(oldUID: oldUID, newUID: newUID)
        }

        outputDeviceWatchdog?.onDeviceHijackBlocked = { [weak self] _, _ in
            self?.statsManager.increment(stat: .outputHijacksBlocked)
            self?.statusBarController?.flashOnAirIndicator()
        }

        outputDeviceWatchdog?.onDeviceMatchAmbiguous = { _, _ in
            // Ambiguous name match — multiple output devices share the same name
        }

        outputDeviceWatchdog?.onManualChangePaused = { [weak self] in
            self?.statusBarController?.flashOnAirIndicator()
        }

        outputDeviceWatchdog?.onPauseResumed = { [weak self] in
            self?.statusBarController?.flashOnAirIndicator()
        }
    }

    private func setupVolumeGuard() {
        guard let audioManager = audioDeviceManager else { return }
        
        volumeGuard = VolumeGuard(audioDeviceManager: audioManager)
        
        volumeGuard?.onVolumeCorrected = { [weak self] _, _ in
            self?.statsManager.increment(stat: .volumeCorrections)
        }

        volumeGuard?.onManualVolumeChangeDetected = { [weak self] in
            self?.statusBarController?.flashOnAirIndicator()
        }

        volumeGuard?.onThrottleStateChanged = { [weak self] isThrottled in
            if isThrottled {
                self?.statusBarController?.flashOnAirIndicator()
            }
        }
    }
    
    private func setupActivityMonitor() {
        guard let audioManager = audioDeviceManager else { return }
        
        activityMonitor = ActivityMonitor(audioDeviceManager: audioManager)
        
        // Listen to meeting end events
        activityMonitor?.onMeetingEnded = { [weak self] in
            guard let self = self,
                  self.preferencesManager.volumeControlStrategy == .resetWhenMicStops else { return }
            
                guard let device = self.audioDeviceManager?.defaultInputDevice,
                  let currentVolume = self.audioDeviceManager?.getInputVolume(for: device) else { return }
            
            let targetLevel = self.preferencesManager.targetVolume
            
            if currentVolume < targetLevel {
                self.volumeGuard?.setVolume(level: targetLevel)
                self.statsManager.increment(stat: .volumeResets)
            }
        }
    }
    
    private func applyStoredPreferences() {
        NSLog("[MicGuard.App] applyStoredPreferences: lockEnabled=\(preferencesManager.inputDeviceLockEnabled) priority=\(preferencesManager.preferredInputDeviceOrder)")
        // Apply input device lock if enabled
        if preferencesManager.inputDeviceLockEnabled {
            let priorityOrder = preferencesManager.preferredInputDeviceOrder
            if !priorityOrder.isEmpty {
                deviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
            } else {
                NSLog("[MicGuard.App] applyStoredPreferences: lock enabled but priority is empty — watchdog NOT started")
            }
        } else {
            NSLog("[MicGuard.App] applyStoredPreferences: lock is DISABLED — watchdog NOT started")
        }
        updateActivityMonitorDeviceOverride()

        // Apply output device lock if enabled
        if preferencesManager.outputDeviceLockEnabled {
            let priorityOrder = preferencesManager.preferredOutputDeviceOrder
            if !priorityOrder.isEmpty {
                outputDeviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
            }
        }

        // Apply volume control strategy
        applyVolumeControlStrategy()
    }
    
    private func applyVolumeControlStrategy() {
        let strategy = preferencesManager.volumeControlStrategy
        let targetVol = preferencesManager.targetVolume
        
        // ActivityMonitor ALWAYS runs (for ON AIR indicator and input level display)
        activityMonitor?.startMonitoring()
        
        switch strategy {
        case .none:
            volumeGuard?.stopGuarding()
            
        case .lockVolume:
            volumeGuard?.startGuarding(targetVolume: targetVol)
            
        case .resetWhenMicStops:
            volumeGuard?.stopGuarding()
        }
    }
    
    private func setupNotificationObservers() {
        // Auto-switch output device on connect
        audioDeviceManager?.devicesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleOutputAutoSwitch()
            }
            .store(in: &cancellables)

        // Observe preferences changes via Combine
        preferencesManager.preferencesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                self?.handlePreferenceChange(key: key)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.addObserver(
            forName: .preferredInputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let _ = notification.object as? String else { return }

            // Update device watchdog if enabled
            if self.preferencesManager.inputDeviceLockEnabled {
                self.deviceWatchdog?.stopWatching()
                let priorityOrder = self.preferencesManager.preferredInputDeviceOrder
                if !priorityOrder.isEmpty {
                    self.deviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
                }
            }
            self.updateActivityMonitorDeviceOverride()
        }

        NotificationCenter.default.addObserver(
            forName: .preferredOutputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let _ = notification.object as? String else { return }

            // Update output device watchdog if enabled
            if self.preferencesManager.outputDeviceLockEnabled {
                self.outputDeviceWatchdog?.stopWatching()
                let priorityOrder = self.preferencesManager.preferredOutputDeviceOrder
                if !priorityOrder.isEmpty {
                    self.outputDeviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
                }
            }
        }
    }
    
    private func handleOutputAutoSwitch() {
        guard preferencesManager.outputAutoSwitchEnabled,
              let audioManager = audioDeviceManager else { return }

        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard !priorityOrder.isEmpty else { return }

        // Find the highest-priority connected output device
        var bestDevice: AudioDevice?
        for uid in priorityOrder {
            if let device = audioManager.device(forUID: uid), device.isOutput {
                bestDevice = device
                break
            }
            // Try name-based fallback
            if let name = preferencesManager.cachedDeviceName(for: uid) {
                let matches = audioManager.outputDevices(withName: name)
                if matches.count == 1 {
                    bestDevice = matches[0]
                    preferencesManager.replaceOutputDeviceUID(oldUID: uid, newUID: matches[0].uid)
                    break
                }
            }
        }

        guard let target = bestDevice,
              let current = audioManager.defaultOutputDevice,
              current.uid != target.uid else { return }

        _ = audioManager.setDefaultOutputDevice(target)
        statsManager.increment(stat: .outputHijacksBlocked)
        statusBarController?.flashOnAirIndicator()
    }

    /// Tells ActivityMonitor which device to treat as the "in use" source for the On Air indicator.
    /// When the input lock is active, we track the locked device directly so the indicator stays
    /// correct even if macOS briefly switches the system default to AirPods.
    private func updateActivityMonitorDeviceOverride() {
        guard preferencesManager.inputDeviceLockEnabled else {
            activityMonitor?.overrideMonitoredDevice = nil
            NSLog("[MicGuard.App] override cleared (lock disabled)")
            return
        }
        let priorityOrder = preferencesManager.preferredInputDeviceOrder
        for uid in priorityOrder {
            if let device = audioDeviceManager?.device(forUID: uid), device.isInput {
                activityMonitor?.overrideMonitoredDevice = device
                NSLog("[MicGuard.App] override set to \(device.name)")
                return
            }
            if let name = preferencesManager.cachedDeviceName(for: uid),
               let device = audioDeviceManager?.inputDevices(withName: name).first {
                activityMonitor?.overrideMonitoredDevice = device
                NSLog("[MicGuard.App] override set to \(device.name) (name-matched)")
                return
            }
        }
        activityMonitor?.overrideMonitoredDevice = nil
        NSLog("[MicGuard.App] override cleared (no preferred device available)")
    }

    private func handlePreferenceChange(key: String) {
        // Handle Target Volume Change
        if key == "TargetVolume" {
            let newVolume = preferencesManager.targetVolume
            volumeGuard?.updateTargetVolume(newVolume)
            
            // Explicitly set the volume immediately for better UX
            // This ensures the slider feels responsive even if locking is disabled
            volumeGuard?.setVolume(level: newVolume)
        }
        
        // Handle Volume Strategy Change
        if key == "VolumeControlStrategy" {
            applyVolumeControlStrategy()
        }
        
        // Handle Input Device Lock Toggle
        if key == "InputDeviceLockEnabled" {
            if preferencesManager.inputDeviceLockEnabled {
                let priorityOrder = preferencesManager.preferredInputDeviceOrder
                if !priorityOrder.isEmpty {
                    deviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
                }
            } else {
                deviceWatchdog?.stopWatching()
            }
            updateActivityMonitorDeviceOverride()
        }

        // Handle Output Device Lock Toggle
        if key == "OutputDeviceLockEnabled" {
            if preferencesManager.outputDeviceLockEnabled {
                let priorityOrder = preferencesManager.preferredOutputDeviceOrder
                if !priorityOrder.isEmpty {
                    outputDeviceWatchdog?.startWatching(devicePriorityOrder: priorityOrder)
                }
            } else {
                outputDeviceWatchdog?.stopWatching()
            }
        }
    }
}
