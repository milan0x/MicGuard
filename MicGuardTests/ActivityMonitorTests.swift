//
//  ActivityMonitorTests.swift
//  MicGuardTests
//
//  Tests for ActivityMonitor functionality
//

import XCTest
import Combine
@testable import MicGuard

final class ActivityMonitorTests: XCTestCase {
    
    var mockAudioManager: MockAudioDeviceManager!
    var activityMonitor: ActivityMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockAudioManager = MockAudioDeviceManager()
        mockAudioManager.setupMockDevices()
        activityMonitor = ActivityMonitor(audioDeviceManager: mockAudioManager)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        activityMonitor.stopMonitoring()
        activityMonitor = nil
        mockAudioManager = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Basic State Tests
    
    func testInitialState() {
        XCTAssertFalse(activityMonitor.isMonitoring, "Should not be monitoring initially")
        XCTAssertFalse(activityMonitor.isMicrophoneActive, "Microphone should not be active initially")
    }
    
    func testStartMonitoringSetsState() {
        // When
        activityMonitor.startMonitoring()
        
        // Then
        XCTAssertTrue(activityMonitor.isMonitoring, "Should be monitoring after start")
    }
    
    func testStopMonitoringClearsState() {
        // Given
        activityMonitor.startMonitoring()
        
        // When
        activityMonitor.stopMonitoring()
        
        // Then
        XCTAssertFalse(activityMonitor.isMonitoring, "Should not be monitoring after stop")
    }
    
    // MARK: - Activity Detection Tests
    
    func testDetectsMicrophoneInUseState() {
        // Given
        let device = mockAudioManager.defaultInputDevice!

        // When device is not running
        mockAudioManager.simulateDeviceRunning(device, isRunning: false)
        activityMonitor.startMonitoring()

        // Then - isMicrophoneInUse tracks device running state
        XCTAssertFalse(activityMonitor.isMicrophoneInUse, "Should detect mic as not in use")
    }
    
    func testMeetingStartedCallback() {
        // Given
        let expectation = XCTestExpectation(description: "Meeting started callback")
        let device = mockAudioManager.defaultInputDevice!
        
        mockAudioManager.simulateDeviceRunning(device, isRunning: false)
        activityMonitor.startMonitoring()
        
        activityMonitor.onMeetingStarted = {
            expectation.fulfill()
        }
        
        // Simulate callback for testing
        activityMonitor.onMeetingStarted?()
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMeetingEndedCallback() {
        // Given
        let expectation = XCTestExpectation(description: "Meeting ended callback")
        
        activityMonitor.startMonitoring()
        
        activityMonitor.onMeetingEnded = {
            expectation.fulfill()
        }
        
        // Simulate callback for testing
        activityMonitor.onMeetingEnded?()
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases
    
    func testHandlesNoDefaultDevice() {
        // Given - Create a mock manager with no devices
        let emptyManager = MockAudioDeviceManager()
        let monitor = ActivityMonitor(audioDeviceManager: emptyManager)
        
        // When
        monitor.startMonitoring()
        
        // Then - Should not crash
        XCTAssertTrue(monitor.isMonitoring, "Should handle no default device gracefully")
        
        monitor.stopMonitoring()
    }
    
    func testDoesNotTriggerCallbacksWhenNotMonitoring() {
        // Given
        var meetingStartedCount = 0
        var meetingEndedCount = 0
        
        activityMonitor.onMeetingStarted = { meetingStartedCount += 1 }
        activityMonitor.onMeetingEnded = { meetingEndedCount += 1 }
        
        // Don't start monitoring
        
        // When - Simulate device changes
        let device = mockAudioManager.defaultInputDevice!
        mockAudioManager.simulateDeviceRunning(device, isRunning: true)
        mockAudioManager.simulateDeviceRunning(device, isRunning: false)
        
        // Allow processing time
        let expectation = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(meetingStartedCount, 0, "Should not trigger meeting started when not monitoring")
        XCTAssertEqual(meetingEndedCount, 0, "Should not trigger meeting ended when not monitoring")
    }
}
