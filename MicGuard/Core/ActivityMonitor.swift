//
//  ActivityMonitor.swift
//  MicGuard
//
//  Monitors microphone activity to detect when meetings end
//

import Foundation
import CoreAudio
import Combine

// MARK: - Protocol for Testability

protocol ActivityMonitorProtocol {
    var isMonitoring: Bool { get }
    var isMicrophoneActive: Bool { get }
    var isMicrophoneInUse: Bool { get }
    var currentMicUsageType: MicUsageType { get }

    func startMonitoring()
    func stopMonitoring()

    var onMeetingStarted: (() -> Void)? { get set }
    var onMeetingEnded: (() -> Void)? { get set }
    var micInUsePublisher: PassthroughSubject<Bool, Never> { get }
    var micUsageTypePublisher: PassthroughSubject<MicUsageType, Never> { get }
}

// MARK: - ActivityMonitor Implementation

class ActivityMonitor: ActivityMonitorProtocol {
    
    // MARK: - Properties
    
    private let audioDeviceManager: AudioDeviceManaging
    private let processMonitor: ProcessMonitoring

    private(set) var isMonitoring: Bool = false
    private(set) var isMicrophoneActive: Bool = false
    private(set) var isMicrophoneInUse: Bool = false
    private(set) var currentMicUsageType: MicUsageType = .none

    /// When the input device lock is active, monitor this device instead of the system default.
    /// Prevents On Air indicator from disappearing when macOS briefly switches to AirPods.
    var overrideMonitoredDevice: AudioDevice?

    
    // Audio level tracking
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0
    private var lastInputLevel: Float = 0.0
    private var lastLevelChangeTime: Date = Date()
    private let micInactivityThreshold: TimeInterval = 2.0 // 2 seconds
    
    // Callbacks
    var onMeetingStarted: (() -> Void)?
    var onMeetingEnded: (() -> Void)?
    
    // Publisher for mic in use state (whether an app is using the mic)
    let micInUsePublisher = PassthroughSubject<Bool, Never>()
    
    // Publisher for mic usage type (WebRTC vs Non-RTC)
    let micUsageTypePublisher = PassthroughSubject<MicUsageType, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(audioDeviceManager: AudioDeviceManaging, processMonitor: ProcessMonitoring = ProcessMonitor()) {
        self.audioDeviceManager = audioDeviceManager
        self.processMonitor = processMonitor
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Reset state
        lastInputLevel = 0.0
        lastLevelChangeTime = Date()
        isMicrophoneActive = false
        isMicrophoneInUse = false
        
        // Subscribe to event-driven running state changes from CoreAudio listener
        // This fires immediately when any app starts/stops using the mic device,
        // rather than waiting for the next poll interval.
        audioDeviceManager.inputDeviceRunningChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.pollInputLevel()
            }
            .store(in: &cancellables)

        // Re-poll whenever the system default input changes so we immediately
        // re-check the locked/preferred device rather than waiting up to 5s.
        audioDeviceManager.defaultInputChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.pollInputLevel()
            }
            .store(in: &cancellables)

        // Start polling timer as fallback
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollInputLevel()
        }

        // Initial poll
        pollInputLevel()
        
    }
    
    func stopMonitoring() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        cancellables.removeAll()
        
    }
    
    // MARK: - Private Methods - Audio Level Polling

    /// Scan every real input device — return true if any is hot. Skips virtual /
    /// aggregate transports to avoid false positives from loopback drivers
    /// (Teams Audio, BlackHole, etc.).
    private func checkAnyMicInUse() -> Bool {
        for device in audioDeviceManager.inputDevices {
            if device.isLikelyUnsettable { continue }
            if audioDeviceManager.isDeviceRunning(device) {
                return true
            }
        }
        return false
    }

    private func pollInputLevel() {
        guard isMonitoring,
              let device = overrideMonitoredDevice ?? audioDeviceManager.defaultInputDevice else {
            if isMicrophoneInUse {
                isMicrophoneInUse = false
                micInUsePublisher.send(false)
            }
            return
        }

        let isRunning = checkAnyMicInUse()

        if isRunning != isMicrophoneInUse {
            MGLog.debug("[MicGuard.Activity] pollInputLevel polled=\(device.name) override=\(overrideMonitoredDevice?.name ?? "nil") systemDefault=\(audioDeviceManager.defaultInputDevice?.name ?? "nil") isRunning=\(isRunning) (was \(isMicrophoneInUse))")
            isMicrophoneInUse = isRunning
            micInUsePublisher.send(isRunning)
        }
        
        // Detect process type when mic is in use
        if isRunning {
            let usageType = processMonitor.detectActiveAudioProcessType()
            if usageType != currentMicUsageType {
                currentMicUsageType = usageType
                micUsageTypePublisher.send(usageType)
            }
        } else {
            // Reset to none when mic is not in use
            if currentMicUsageType != .none {
                currentMicUsageType = .none
                micUsageTypePublisher.send(.none)
            }
        }

        // Read current input volume — used purely to detect "meeting active" vs idle
        // by watching for level fluctuations. Not surfaced to UI.
        guard let level = audioDeviceManager.getInputVolume(for: device) else {
            return
        }

        // Check if level has changed
        let levelChanged = abs(level - lastInputLevel) > 0.001 // Tolerance for float comparison
        
        if levelChanged {
            // Level changed - microphone is being actively used
            lastInputLevel = level
            lastLevelChangeTime = Date()
            
            if !isMicrophoneActive {
                isMicrophoneActive = true
                onMeetingStarted?()
            }
        } else {
            // Level hasn't changed - check if it's been too long
            let timeSinceLastChange = Date().timeIntervalSince(lastLevelChangeTime)
            
            if timeSinceLastChange >= micInactivityThreshold && isMicrophoneActive {
                isMicrophoneActive = false
                onMeetingEnded?()
            }
        }
        
    }
}
