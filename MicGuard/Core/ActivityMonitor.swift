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
    var currentInputLevel: Float { get }
    var currentMicUsageType: MicUsageType { get }

    func startMonitoring()
    func stopMonitoring()

    var onMeetingStarted: (() -> Void)? { get set }
    var onMeetingEnded: (() -> Void)? { get set }
    var inputLevelPublisher: PassthroughSubject<Float, Never> { get }
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
    private(set) var currentInputLevel: Float = 0.0
    private(set) var currentMicUsageType: MicUsageType = .none
    
    // Audio level tracking
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 5.0
    private var lastInputLevel: Float = 0.0
    private var lastLevelChangeTime: Date = Date()
    private let micInactivityThreshold: TimeInterval = 2.0 // 2 seconds
    
    // Callbacks
    var onMeetingStarted: (() -> Void)?
    var onMeetingEnded: (() -> Void)?
    
    // Publisher for input level updates
    let inputLevelPublisher = PassthroughSubject<Float, Never>()

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
    
    private func pollInputLevel() {
        guard isMonitoring,
              let device = audioDeviceManager.defaultInputDevice else {
            currentInputLevel = 0.0
            inputLevelPublisher.send(0.0)
            if isMicrophoneInUse {
                isMicrophoneInUse = false
                micInUsePublisher.send(false)
            }
            return
        }

        // Check if mic is being used by any app (device is running)
        let isRunning = audioDeviceManager.isDeviceRunning(device)

        if isRunning != isMicrophoneInUse {
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

        // Get the current input volume level
        guard let level = audioDeviceManager.getInputVolume(for: device) else {
            currentInputLevel = 0.0
            inputLevelPublisher.send(0.0)
            return
        }

        currentInputLevel = level
        inputLevelPublisher.send(level)
        
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
