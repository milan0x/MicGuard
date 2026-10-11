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

    
    // Polling fallback for the event-driven running-state listener.
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0
    
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

        // Polling fallback. .common mode so it keeps firing while the status-item
        // context menu is tracking.
        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollInputLevel()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer

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

    // internal (not private) so tests can drive polls — the real triggers are a
    // CoreAudio listener and a timer the mock layer can't fire.
    func pollInputLevel() {
        guard isMonitoring else { return }

        // No resolvable device (list mid-refresh, nothing connected): treat as idle.
        guard let device = overrideMonitoredDevice ?? audioDeviceManager.defaultInputDevice else {
            setMicInUse(false, polled: nil)
            return
        }

        setMicInUse(checkAnyMicInUse(), polled: device)

        // Detect process type while the mic is held.
        if isMicrophoneInUse {
            let usageType = processMonitor.detectActiveAudioProcessType()
            if usageType != currentMicUsageType {
                currentMicUsageType = usageType
                micUsageTypePublisher.send(usageType)
            }
        } else if currentMicUsageType != .none {
            currentMicUsageType = .none
            micUsageTypePublisher.send(.none)
        }
    }

    /// Single source of truth for "an app holds the mic". A meeting is exactly
    /// the span during which some process keeps an input device running —
    /// `onMeetingStarted` / `onMeetingEnded` fire on the edges of that state so
    /// the "reset when mic stops" strategy acts when the mic is actually released,
    /// never on volume churn while a call is still live.
    private func setMicInUse(_ inUse: Bool, polled device: AudioDevice?) {
        guard inUse != isMicrophoneInUse else { return }
        MGLog.debug("[MicGuard.Activity] mic in use=\(inUse) polled=\(device?.name ?? "nil") override=\(overrideMonitoredDevice?.name ?? "nil") systemDefault=\(audioDeviceManager.defaultInputDevice?.name ?? "nil")")
        isMicrophoneInUse = inUse
        isMicrophoneActive = inUse
        micInUsePublisher.send(inUse)
        if inUse {
            onMeetingStarted?()
        } else {
            onMeetingEnded?()
        }
    }
}
