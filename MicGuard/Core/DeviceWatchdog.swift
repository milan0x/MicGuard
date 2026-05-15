//
//  DeviceWatchdog.swift
//  MicGuard
//
//  Monitors system default device changes and enforces user's preferred device
//

import Foundation
import Combine
import AppKit

// MARK: - Protocol for Testability

protocol DeviceWatchdogProtocol {
    var isWatching: Bool { get }
    var isPaused: Bool { get }
    var devicePriorityOrder: [String] { get }

    func startWatching(devicePriorityOrder: [String])
    func stopWatching()
    func updateDevicePriorityOrder(_ order: [String])

    var onDeviceHijackBlocked: ((String, String) -> Void)? { get set }

    /// Resolves a cached name for a given UID (provided by PreferencesManager)
    var nameForUID: ((String) -> String?)? { get set }
    /// Called when a device is matched by name and its stored UID needs updating: (oldUID, newUID)
    var onDeviceUIDUpdated: ((String, String) -> Void)? { get set }
    /// Called when multiple devices share the same name, making name-based matching ambiguous: (name, count)
    var onDeviceMatchAmbiguous: ((String, Int) -> Void)? { get set }
    /// Called when enforcement is paused due to manual change in System Settings
    var onManualChangePaused: (() -> Void)? { get set }
    /// Called when enforcement resumes after a manual change pause
    var onPauseResumed: (() -> Void)? { get set }
}

// MARK: - BaseDeviceWatchdog

/// Common logic for input and output device watchdogs.
/// Subclasses provide direction-specific hooks via closures.
class BaseDeviceWatchdog: DeviceWatchdogProtocol {

    // MARK: - Properties

    let audioDeviceManager: AudioDeviceManaging
    var cancellables = Set<AnyCancellable>()

    private(set) var isWatching: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var preferredDeviceUID: String?
    private(set) var devicePriorityOrder: [String] = []

    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    // Manual change pause mechanism
    private let pauseDuration: TimeInterval
    private var pauseTimer: DispatchWorkItem?
    private var appDeactivationObserver: NSObjectProtocol?

    // Periodic verification: macOS (especially Bluetooth/AirPods routing) can switch the default
    // device without reliably firing kAudioHardwarePropertyDefaultInputDevice. Poll every 3s as
    // a safety net so the lock catches any switch that slips past the event-driven path.
    private var verificationTimer: Timer?
    private let verificationInterval: TimeInterval = 3.0

    var onDeviceHijackBlocked: ((String, String) -> Void)?
    var nameForUID: ((String) -> String?)?
    var onDeviceUIDUpdated: ((String, String) -> Void)?
    var onDeviceMatchAmbiguous: ((String, Int) -> Void)?
    var onManualChangePaused: (() -> Void)?
    var onPauseResumed: (() -> Void)?

    // MARK: - Direction hooks (set by subclasses)

    var deviceChangedPublisher: (() -> PassthroughSubject<AudioDevice?, Never>)!
    var getDefaultDevice: (() -> AudioDevice?)!
    var setDefaultDevice: ((AudioDevice) -> Bool)!
    var devicesWithName: ((String) -> [AudioDevice])!
    var selectBestDevice: (() -> AudioDevice?)!

    // MARK: - Initialization

    init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1, pauseDuration: TimeInterval = 300) {
        self.audioDeviceManager = audioDeviceManager
        self.debounceInterval = debounceInterval
        self.pauseDuration = pauseDuration
    }

    // MARK: - Public Methods

    func startWatching(devicePriorityOrder: [String]) {
        self.devicePriorityOrder = devicePriorityOrder
        self.preferredDeviceUID = devicePriorityOrder.first

        NSLog("[MicGuard.Watchdog] startWatching priority=\(devicePriorityOrder)")

        guard !isWatching else {
            NSLog("[MicGuard.Watchdog] startWatching: already watching, only priority updated")
            return
        }
        isWatching = true

        deviceChangedPublisher()
            .sink { [weak self] newDevice in
                self?.handleDeviceChange(newDevice: newDevice)
            }
            .store(in: &cancellables)

        audioDeviceManager.devicesChangedPublisher
            .sink { [weak self] in
                self?.handleDeviceListChange()
            }
            .store(in: &cancellables)

        enforcePreferredDevice()
        startVerificationTimer()
    }

    func stopWatching() {
        isWatching = false
        resumeFromPause()
        cancellables.removeAll()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        stopVerificationTimer()
    }

    func updatePreferredDevice(uid: String) {
        updateDevicePriorityOrder([uid])
    }

    func updateDevicePriorityOrder(_ order: [String]) {
        devicePriorityOrder = order
        preferredDeviceUID = order.first

        if isWatching {
            enforcePreferredDevice()
        }
    }

    // MARK: - Device Change Handling

    private func handleDeviceChange(newDevice: AudioDevice?) {
        NSLog("[MicGuard.Watchdog] handleDeviceChange newDevice=\(newDevice?.name ?? "nil") isWatching=\(isWatching) isPaused=\(isPaused)")

        guard isWatching else { return }

        // If user is manually changing device in System Settings, pause enforcement
        if isSystemSettingsFrontmost() {
            NSLog("[MicGuard.Watchdog] handleDeviceChange: System Settings frontmost, pausing")
            startPause()
            return
        }

        // If paused, a non-manual device change (e.g., AirPods connecting) resumes enforcement
        if isPaused {
            resumeFromPause()
        }

        guard let bestDevice = selectBestDevice() else {
            NSLog("[MicGuard.Watchdog] handleDeviceChange: selectBestDevice returned nil — priority=\(devicePriorityOrder)")
            return
        }

        NSLog("[MicGuard.Watchdog] handleDeviceChange bestDevice=\(bestDevice.name) priorityOrder=\(devicePriorityOrder)")

        // Enforce immediately when the new default isn't our preferred device.
        // Previously this was debounced, but each rapid-fire macOS event (AirPods HFP/AAC
        // mode switches, re-overrides) would cancel the pending work item and reschedule —
        // starving enforcement when events arrived faster than the debounce interval.
        if newDevice?.uid != bestDevice.uid {
            enforcePreferredDevice()
        }
    }

    func handleDeviceListChange() {
        NSLog("[MicGuard.Watchdog] handleDeviceListChange isWatching=\(isWatching)")
        guard isWatching else { return }

        // A device list change (connect/disconnect) while paused resumes enforcement
        if isPaused {
            resumeFromPause()
        }

        if let bestDevice = selectBestDevice() {
            let currentDefault = getDefaultDevice()
            NSLog("[MicGuard.Watchdog] handleDeviceListChange best=\(bestDevice.name) current=\(currentDefault?.name ?? "nil")")
            if currentDefault?.uid != bestDevice.uid {
                enforcePreferredDevice()
            }
        }

        // macOS often changes the default device *after* the device-list change event fires
        // (observed with AirPods and other Bluetooth devices). Schedule two delayed checks so
        // we catch the switch even when kAudioHardwarePropertyDefaultInputDevice doesn't fire.
        scheduleDelayedCheck(after: 0.3)
        scheduleDelayedCheck(after: 1.0)
    }

    private func scheduleDelayedCheck(after delay: TimeInterval) {
        // One-shot timer in .common mode so it fires even while NSMenu is tracking.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, self.isWatching, !self.isPaused else { return }
            guard let bestDevice = self.selectBestDevice() else { return }
            let currentDefault = self.getDefaultDevice()
            if currentDefault?.uid != bestDevice.uid {
                self.enforcePreferredDevice()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func enforcePreferredDevice() {
        guard !isPaused else {
            NSLog("[MicGuard.Watchdog] enforcePreferredDevice: paused, skipping")
            return
        }
        guard let bestDevice = selectBestDevice() else {
            NSLog("[MicGuard.Watchdog] enforcePreferredDevice: no best device, skipping")
            return
        }

        let currentDefault = getDefaultDevice()
        guard currentDefault?.uid != bestDevice.uid else {
            NSLog("[MicGuard.Watchdog] enforcePreferredDevice: already on \(bestDevice.name), nothing to do")
            return
        }

        let attemptedDeviceName = currentDefault?.name ?? "Unknown"
        NSLog("[MicGuard.Watchdog] enforcePreferredDevice: switching from \(attemptedDeviceName) to \(bestDevice.name)")

        let setResult = setDefaultDevice(bestDevice)
        NSLog("[MicGuard.Watchdog] enforcePreferredDevice: setDefaultDevice returned \(setResult)")

        if setResult {
            // Verify immediately whether the change actually stuck at the CoreAudio layer.
            let verifyDefault = getDefaultDevice()
            NSLog("[MicGuard.Watchdog] enforcePreferredDevice: post-set verification, currentDefault=\(verifyDefault?.name ?? "nil")")

            onDeviceHijackBlocked?(attemptedDeviceName, bestDevice.name)
            // macOS (especially with AirPods) can re-override within milliseconds.
            // Verify the change stuck after a short delay and silently re-apply if needed.
            scheduleEnforcementVerification()
        }
    }

    private func scheduleEnforcementVerification() {
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self = self, self.isWatching, !self.isPaused else { return }
            guard let bestDevice = self.selectBestDevice() else { return }
            let currentDefault = self.getDefaultDevice()
            if currentDefault?.uid != bestDevice.uid {
                _ = self.setDefaultDevice(bestDevice)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startVerificationTimer() {
        stopVerificationTimer()
        // Use .common mode so the timer fires even while NSMenu's eventTracking loop is active.
        // Timer.scheduledTimer uses .defaultRunLoopMode which is suspended during menu display.
        let timer = Timer(timeInterval: verificationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isWatching, !self.isPaused else { return }
            guard let bestDevice = self.selectBestDevice() else { return }
            let currentDefault = self.getDefaultDevice()
            if currentDefault?.uid != bestDevice.uid {
                NSLog("[MicGuard.Watchdog] verificationTimer: drift detected, current=\(currentDefault?.name ?? "nil") best=\(bestDevice.name)")
                self.enforcePreferredDevice()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        verificationTimer = timer
        NSLog("[MicGuard.Watchdog] verificationTimer started (\(verificationInterval)s interval, .common mode)")
    }

    private func stopVerificationTimer() {
        verificationTimer?.invalidate()
        verificationTimer = nil
    }

    // MARK: - Manual Change Pause

    private func startPause() {
        guard !isPaused else { return }
        isPaused = true

        // Cancel any pending enforcement
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        onManualChangePaused?()

        // Schedule timeout to resume
        pauseTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.resumeFromPause()
        }
        pauseTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration, execute: timer)

        // Also resume when System Settings loses focus
        appDeactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isPaused else { return }
            // If the newly activated app is NOT System Settings, resume
            if !self.isSystemSettingsFrontmost() {
                self.resumeFromPause()
            }
        }
    }

    private func resumeFromPause() {
        let wasPaused = isPaused
        isPaused = false
        pauseTimer?.cancel()
        pauseTimer = nil

        if let observer = appDeactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appDeactivationObserver = nil
        }

        if wasPaused {
            onPauseResumed?()
            // Re-enforce after resuming
            if isWatching {
                enforcePreferredDevice()
            }
        }
    }

    // MARK: - Helper Methods

    private func isSystemSettingsFrontmost() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmost.bundleIdentifier else { return false }

        return bundleId == "com.apple.systempreferences" ||  // macOS 12 and earlier
               bundleId == "com.apple.Settings"              // macOS 13+
    }

    // MARK: - Name-Based Matching Helpers

    /// Try to find a device by UID first, then fall back to name match. Updates UID if matched by name.
    func findDeviceByUIDOrName(_ uid: String) -> AudioDevice? {
        if let device = audioDeviceManager.device(forUID: uid) {
            return device
        }

        if let name = nameForUID?(uid) {
            let nameMatches = devicesWithName(name)
            if nameMatches.count == 1 {
                let matchedDevice = nameMatches[0]
                if let index = devicePriorityOrder.firstIndex(of: uid) {
                    devicePriorityOrder[index] = matchedDevice.uid
                    preferredDeviceUID = devicePriorityOrder.first
                }
                onDeviceUIDUpdated?(uid, matchedDevice.uid)
                return matchedDevice
            } else if nameMatches.count > 1 {
                onDeviceMatchAmbiguous?(name, nameMatches.count)
            }
        }

        return nil
    }
}

// MARK: - DeviceWatchdog (Input)

class DeviceWatchdog: BaseDeviceWatchdog {

    override init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1, pauseDuration: TimeInterval = 300) {
        super.init(audioDeviceManager: audioDeviceManager, debounceInterval: debounceInterval, pauseDuration: pauseDuration)

        deviceChangedPublisher = { [unowned self] in self.audioDeviceManager.defaultInputChangedPublisher }
        getDefaultDevice = { [unowned self] in self.audioDeviceManager.defaultInputDevice }
        setDefaultDevice = { [unowned self] in self.audioDeviceManager.setDefaultInputDevice($0) }
        devicesWithName = { [unowned self] in self.audioDeviceManager.inputDevices(withName: $0) }
        selectBestDevice = { [unowned self] in self.selectBestAvailableDevice() }
    }

    /// Select the best available device from the priority list
    private func selectBestAvailableDevice() -> AudioDevice? {
        for uid in devicePriorityOrder {
            if let device = findDeviceByUIDOrName(uid) {
                return device
            }
        }
        // If no devices in priority list are available, return system default
        return audioDeviceManager.defaultInputDevice
    }
}

// MARK: - OutputDeviceWatchdog

class OutputDeviceWatchdog: BaseDeviceWatchdog {

    override init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1, pauseDuration: TimeInterval = 300) {
        super.init(audioDeviceManager: audioDeviceManager, debounceInterval: debounceInterval, pauseDuration: pauseDuration)

        deviceChangedPublisher = { [unowned self] in self.audioDeviceManager.defaultOutputChangedPublisher }
        getDefaultDevice = { [unowned self] in self.audioDeviceManager.defaultOutputDevice }
        setDefaultDevice = { [unowned self] in self.audioDeviceManager.setDefaultOutputDevice($0) }
        devicesWithName = { [unowned self] in self.audioDeviceManager.outputDevices(withName: $0) }
        selectBestDevice = { [unowned self] in self.selectPreferredDevice() }
    }

    /// Select the best available output device from the priority list
    private func selectPreferredDevice() -> AudioDevice? {
        for uid in devicePriorityOrder {
            if let device = findDeviceByUIDOrName(uid) {
                return device
            }
        }
        return audioDeviceManager.defaultOutputDevice
    }
}
