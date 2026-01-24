//
//  OutputDeviceWatchdogTests.swift
//  MicGuardTests
//
//  Tests for OutputDeviceWatchdog functionality
//

import XCTest
import Combine
@testable import MicGuard

final class OutputDeviceWatchdogTests: XCTestCase {

    var mockAudioManager: MockAudioDeviceManager!
    var watchdog: OutputDeviceWatchdog!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockAudioManager = MockAudioDeviceManager()
        mockAudioManager.setupMockDevices()
        watchdog = OutputDeviceWatchdog(audioDeviceManager: mockAudioManager, debounceInterval: 0.01)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        watchdog.stopWatching()
        watchdog = nil
        mockAudioManager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Basic State Tests

    func testInitialState() {
        XCTAssertFalse(watchdog.isWatching)
        XCTAssertNil(watchdog.preferredDeviceUID)
    }

    func testStartWatchingSetsState() {
        let speakers = mockAudioManager.outputDevices.first { $0.uid == "BuiltInSpeakers" }!

        watchdog.startWatching(devicePriorityOrder: [speakers.uid])

        XCTAssertTrue(watchdog.isWatching)
        XCTAssertEqual(watchdog.preferredDeviceUID, speakers.uid)
    }

    func testStopWatchingClearsState() {
        watchdog.startWatching(devicePriorityOrder: ["BuiltInSpeakers"])
        watchdog.stopWatching()

        XCTAssertFalse(watchdog.isWatching)
    }

    // MARK: - Output Device Hijack Prevention

    func testBlocksOutputDeviceHijack() {
        let expectation = XCTestExpectation(description: "Output device hijack blocked")
        let speakers = mockAudioManager.outputDevices.first { $0.uid == "BuiltInSpeakers" }!
        let hdmi = mockAudioManager.outputDevices.first { $0.uid == "HDMIOutput" }!

        // Set speakers as current default
        mockAudioManager.setDefaultOutputDevice(speakers)

        watchdog.startWatching(devicePriorityOrder: [speakers.uid])

        watchdog.onDeviceHijackBlocked = { attemptedDevice, enforcedDevice in
            XCTAssertEqual(attemptedDevice, "LG Monitor")
            XCTAssertEqual(enforcedDevice, "MacBook Pro Speakers")
            expectation.fulfill()
        }

        // Simulate HDMI hijacking output
        mockAudioManager.simulateOutputDeviceSwitch(to: hdmi)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockAudioManager.setDefaultOutputDeviceCalls.last?.uid, speakers.uid)
    }

    func testDoesNotBlockWhenNotWatching() {
        let hdmi = mockAudioManager.outputDevices.first { $0.uid == "HDMIOutput" }!

        var hijackBlocked = false
        watchdog.onDeviceHijackBlocked = { _, _ in
            hijackBlocked = true
        }

        mockAudioManager.simulateOutputDeviceSwitch(to: hdmi)

        let expectation = XCTestExpectation(description: "Wait for debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(hijackBlocked)
    }

    // MARK: - Name-Based Reconnection (uses outputDevices, not inputDevices)

    func testNameBasedReconnectionUsesOutputDevices() {
        let speakers = mockAudioManager.outputDevices.first { $0.uid == "BuiltInSpeakers" }!

        mockAudioManager.setDefaultOutputDevice(speakers)

        watchdog.nameForUID = { uid in
            if uid == "BuiltInSpeakers" { return "MacBook Pro Speakers" }
            return nil
        }

        var uidUpdateCalled = false
        watchdog.onDeviceUIDUpdated = { oldUID, newUID in
            uidUpdateCalled = true
        }

        watchdog.startWatching(devicePriorityOrder: ["BuiltInSpeakers"])
        mockAudioManager.setDefaultOutputDeviceCalls.removeAll()

        // Disconnect the device
        mockAudioManager.simulateDeviceDisconnected(speakers)

        // Reconnect with a new UID but same name
        let reconnectedSpeakers = AudioDevice(
            id: 99,
            uid: "BuiltInSpeakers-NewPort",
            name: "MacBook Pro Speakers",
            isInput: false,
            isOutput: true
        )
        mockAudioManager.simulateDeviceReconnected(reconnectedSpeakers)

        let expectation = XCTestExpectation(description: "Wait for name-based match")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(uidUpdateCalled, "Should find device by name via outputDevices(withName:)")
    }
}
