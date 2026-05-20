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
    var devicePriorityOrder: [String] { get }

    func startWatching(devicePriorityOrder: [String])
    func stopWatching()
    func updateDevicePriorityOrder(_ order: [String])

    var onDeviceHijackBlocked: ((String, String) -> Void)? { get set }
    /// Fires when the watchdog yields after repeated user overrides: (acceptedDeviceName, formerPreferred).
    /// Caller should surface "INPUT/OUTPUT CHANGED" feedback and expose a way to resume.
    var onYielded: ((String, String) -> Void)? { get set }
    /// Fires when the watchdog transitions from yielded → protecting again.
    /// Whether triggered by user (Re-apply) or auto-resume, caller can flash "LOCK ON".
    var onProtectionResumed: (() -> Void)? { get set }

    /// Resolves a cached name for a given UID (provided by PreferencesManager)
    var nameForUID: ((String) -> String?)? { get set }
    /// Called when a device is matched by name and its stored UID needs updating: (oldUID, newUID)
    var onDeviceUIDUpdated: ((String, String) -> Void)? { get set }
    /// Called when multiple devices share the same name, making name-based matching ambiguous: (name, count)
    var onDeviceMatchAmbiguous: ((String, Int) -> Void)? { get set }

    /// Clear the yielded state and resume enforcement immediately.
    func resumeProtection()
}

// MARK: - BaseDeviceWatchdog

/// Common logic for input and output device watchdogs.
/// Subclasses provide direction-specific hooks via closures.
class BaseDeviceWatchdog: DeviceWatchdogProtocol {

    // MARK: - Properties

    let audioDeviceManager: AudioDeviceManaging
    var cancellables = Set<AnyCancellable>()

    private(set) var isWatching: Bool = false
    private(set) var preferredDeviceUID: String?
    private(set) var devicePriorityOrder: [String] = []

    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    // Periodic verification: macOS (especially Bluetooth/AirPods routing) can switch the default
    // device without reliably firing kAudioHardwarePropertyDefaultInputDevice. Poll every 3s as
    // a safety net so the lock catches any switch that slips past the event-driven path.
    private var verificationTimer: Timer?
    private let verificationInterval: TimeInterval = 3.0

    var onDeviceHijackBlocked: ((String, String) -> Void)?
    var onYielded: ((String, String) -> Void)?
    var onProtectionResumed: (() -> Void)?
    var nameForUID: ((String) -> String?)?
    var onDeviceUIDUpdated: ((String, String) -> Void)?
    var onDeviceMatchAmbiguous: ((String, Int) -> Void)?

    // Yield-after-N-hijacks: when the user fights us repeatedly, stop fighting back.
    // Lets them deliberately use a non-preferred device without MicGuard nagging.
    /// When false, the watchdog always reverts — never yields. Set from preference.
    var autoYieldEnabled: Bool = true
    /// When true, the watchdog auto-resumes from yielded state the moment the user
    /// picks the top-priority device (from anywhere — System Settings, popover, etc).
    var autoResumeEnabled: Bool = false
    private(set) var isYielded: Bool = false
    private var recentHijackTimestamps: [Date] = []
    private let yieldThresholdCount: Int = 2
    private let yieldWindow: TimeInterval = 10.0
    private let yieldMinSpread: TimeInterval = 1.0  // filters out Bluetooth flap storms

    // MARK: - Direction hooks (set by subclasses)

    var deviceChangedPublisher: (() -> PassthroughSubject<AudioDevice?, Never>)!
    var getDefaultDevice: (() -> AudioDevice?)!
    var setDefaultDevice: ((AudioDevice) -> Bool)!
    var devicesWithName: ((String) -> [AudioDevice])!
    var selectBestDevice: (() -> AudioDevice?)!

    // MARK: - Initialization

    init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1) {
        self.audioDeviceManager = audioDeviceManager
        self.debounceInterval = debounceInterval
    }

    // MARK: - Public Methods

    func startWatching(devicePriorityOrder: [String]) {
        self.devicePriorityOrder = devicePriorityOrder
        self.preferredDeviceUID = devicePriorityOrder.first

        MGLog.debug("[MicGuard.Watchdog] startWatching priority=\(devicePriorityOrder)")

        guard !isWatching else {
            MGLog.debug("[MicGuard.Watchdog] startWatching: already watching, only priority updated")
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
        isYielded = false
        recentHijackTimestamps.removeAll()
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
        MGLog.debug("[MicGuard.Watchdog] handleDeviceChange newDevice=\(newDevice?.name ?? "nil") isWatching=\(isWatching) isYielded=\(isYielded)")

        guard isWatching else { return }

        // While yielded: check whether the user just navigated back to the top-priority
        // device. If so AND auto-resume is enabled, exit yielded state and resume
        // enforcement. The user's action signals they've "come home" to their preferred.
        if isYielded {
            if autoResumeEnabled,
               let best = selectBestDevice(),
               newDevice?.uid == best.uid {
                MGLog.debug("[MicGuard.Watchdog] auto-resume: user picked top-priority \(best.name)")
                resumeProtection()
            }
            return
        }

        // Always enforce — including when System Settings is frontmost.
        // Lock means "hold the priority device, period." If the user wants to switch,
        // they can do so via MicGuard's popover (which calls setDefault directly,
        // bypassing this enforcement path because the new device becomes #1 priority).

        guard let bestDevice = selectBestDevice() else {
            MGLog.debug("[MicGuard.Watchdog] handleDeviceChange: selectBestDevice returned nil — priority=\(devicePriorityOrder)")
            return
        }

        MGLog.debug("[MicGuard.Watchdog] handleDeviceChange bestDevice=\(bestDevice.name) priorityOrder=\(devicePriorityOrder)")

        // If the user has changed the default away from our preferred device, see
        // whether they've done it repeatedly. If so, yield instead of fighting.
        if newDevice?.uid != bestDevice.uid {
            if shouldYieldToRepeatedOverride() {
                isYielded = true
                recentHijackTimestamps.removeAll()
                MGLog.debug("[MicGuard.Watchdog] yielding — user changed default repeatedly")
                onYielded?(newDevice?.name ?? "Unknown", bestDevice.name)
                return
            }
            enforcePreferredDevice()
        }
    }

    /// Returns true when the user has manually overridden the default ≥ N times
    /// inside the yieldWindow, with at least `yieldMinSpread` between events
    /// (filters out millisecond-fast Bluetooth flap storms).
    /// Returns false when `autoYieldEnabled` is off — caller will always revert.
    private func shouldYieldToRepeatedOverride() -> Bool {
        guard autoYieldEnabled else { return false }

        let now = Date()
        recentHijackTimestamps.removeAll { now.timeIntervalSince($0) > yieldWindow }

        // Ignore events that fire too fast after the last one — that's Bluetooth, not a user.
        if let last = recentHijackTimestamps.last, now.timeIntervalSince(last) < yieldMinSpread {
            return false
        }
        recentHijackTimestamps.append(now)
        return recentHijackTimestamps.count >= yieldThresholdCount
    }

    func resumeProtection() {
        guard isYielded else { return }
        MGLog.debug("[MicGuard.Watchdog] resumeProtection — clearing yield state")
        isYielded = false
        recentHijackTimestamps.removeAll()
        onProtectionResumed?()
        if isWatching {
            enforcePreferredDevice()
        }
    }

    func handleDeviceListChange() {
        MGLog.debug("[MicGuard.Watchdog] handleDeviceListChange isWatching=\(isWatching)")
        guard isWatching, !isYielded else { return }

        if let bestDevice = selectBestDevice() {
            let currentDefault = getDefaultDevice()
            MGLog.debug("[MicGuard.Watchdog] handleDeviceListChange best=\(bestDevice.name) current=\(currentDefault?.name ?? "nil")")
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
            guard let self = self, self.isWatching, !self.isYielded else { return }
            guard let bestDevice = self.selectBestDevice() else { return }
            let currentDefault = self.getDefaultDevice()
            if currentDefault?.uid != bestDevice.uid {
                self.enforcePreferredDevice()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func enforcePreferredDevice() {
        guard !isYielded else {
            MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: yielded, skipping")
            return
        }
        guard let bestDevice = selectBestDevice() else {
            MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: no best device, skipping")
            return
        }

        let currentDefault = getDefaultDevice()
        guard currentDefault?.uid != bestDevice.uid else {
            MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: already on \(bestDevice.name), nothing to do")
            return
        }

        let attemptedDeviceName = currentDefault?.name ?? "Unknown"
        MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: switching from \(attemptedDeviceName) to \(bestDevice.name)")

        let setResult = setDefaultDevice(bestDevice)
        MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: setDefaultDevice returned \(setResult)")

        if setResult {
            // Verify immediately whether the change actually stuck at the CoreAudio layer.
            let verifyDefault = getDefaultDevice()
            MGLog.debug("[MicGuard.Watchdog] enforcePreferredDevice: post-set verification, currentDefault=\(verifyDefault?.name ?? "nil")")

            onDeviceHijackBlocked?(attemptedDeviceName, bestDevice.name)
            // macOS (especially with AirPods) can re-override within milliseconds.
            // Verify the change stuck after a short delay and silently re-apply if needed.
            scheduleEnforcementVerification()
        }
    }

    private func scheduleEnforcementVerification() {
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self = self, self.isWatching, !self.isYielded else { return }
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
            guard self.isWatching, !self.isYielded else { return }
            guard let bestDevice = self.selectBestDevice() else { return }
            let currentDefault = self.getDefaultDevice()
            if currentDefault?.uid != bestDevice.uid {
                MGLog.debug("[MicGuard.Watchdog] verificationTimer: drift detected, current=\(currentDefault?.name ?? "nil") best=\(bestDevice.name)")
                self.enforcePreferredDevice()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        verificationTimer = timer
        MGLog.debug("[MicGuard.Watchdog] verificationTimer started (\(verificationInterval)s interval, .common mode)")
    }

    private func stopVerificationTimer() {
        verificationTimer?.invalidate()
        verificationTimer = nil
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

    override init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1) {
        super.init(audioDeviceManager: audioDeviceManager, debounceInterval: debounceInterval)

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

    override init(audioDeviceManager: AudioDeviceManaging, debounceInterval: TimeInterval = 0.1) {
        super.init(audioDeviceManager: audioDeviceManager, debounceInterval: debounceInterval)

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
