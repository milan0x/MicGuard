//
//  AudioDeviceTests.swift
//  MicGuardTests
//
//  Tests for AudioDevice model
//

import XCTest
@testable import MicGuard

final class AudioDeviceTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testAudioDeviceInitialization() {
        // Given
        let device = AudioDevice(
            id: 42,
            uid: "TestDeviceUID",
            name: "Test Microphone",
            isInput: true,
            isOutput: false
        )
        
        // Then
        XCTAssertEqual(device.id, 42)
        XCTAssertEqual(device.uid, "TestDeviceUID")
        XCTAssertEqual(device.name, "Test Microphone")
        XCTAssertTrue(device.isInput)
        XCTAssertFalse(device.isOutput)
    }
    
    func testAudioDeviceWithBothInputAndOutput() {
        // Given - A device that is both input and output (like AirPods)
        let device = AudioDevice(
            id: 1,
            uid: "AirPodsUID",
            name: "AirPods Pro",
            isInput: true,
            isOutput: true
        )
        
        // Then
        XCTAssertTrue(device.isInput)
        XCTAssertTrue(device.isOutput)
    }
    
    // MARK: - Equatable Tests
    
    func testAudioDeviceEquality() {
        // Given
        let device1 = AudioDevice(id: 1, uid: "SameUID", name: "Device 1", isInput: true, isOutput: false)
        let device2 = AudioDevice(id: 2, uid: "SameUID", name: "Device 2", isInput: false, isOutput: true)
        
        // Then - Devices are equal if they have the same UID
        XCTAssertEqual(device1, device2, "Devices with same UID should be equal")
    }
    
    func testAudioDeviceInequality() {
        // Given
        let device1 = AudioDevice(id: 1, uid: "UID1", name: "Device", isInput: true, isOutput: false)
        let device2 = AudioDevice(id: 1, uid: "UID2", name: "Device", isInput: true, isOutput: false)
        
        // Then - Devices are not equal if they have different UIDs
        XCTAssertNotEqual(device1, device2, "Devices with different UIDs should not be equal")
    }
    
    // MARK: - Hashable Tests
    
    func testAudioDeviceHashable() {
        // Given
        let device1 = AudioDevice(id: 1, uid: "SameUID", name: "Device 1", isInput: true, isOutput: false)
        let device2 = AudioDevice(id: 2, uid: "SameUID", name: "Device 2", isInput: false, isOutput: true)
        
        // Then - Hash values should be the same for equal devices
        XCTAssertEqual(device1.hashValue, device2.hashValue, "Equal devices should have same hash")
    }
    
    func testAudioDeviceInSet() {
        // Given
        let device1 = AudioDevice(id: 1, uid: "UID1", name: "Device 1", isInput: true, isOutput: false)
        let device2 = AudioDevice(id: 2, uid: "UID2", name: "Device 2", isInput: true, isOutput: false)
        let device3 = AudioDevice(id: 3, uid: "UID1", name: "Device 3", isInput: true, isOutput: true) // Same UID as device1
        
        // When
        var deviceSet: Set<AudioDevice> = []
        deviceSet.insert(device1)
        deviceSet.insert(device2)
        deviceSet.insert(device3) // Should not be added (same UID as device1)
        
        // Then
        XCTAssertEqual(deviceSet.count, 2, "Set should only contain 2 unique devices")
        XCTAssertTrue(deviceSet.contains(device1))
        XCTAssertTrue(deviceSet.contains(device2))
    }
    
    // MARK: - Identifiable Tests
    
    func testAudioDeviceIdentifiable() {
        // Given
        let device = AudioDevice(id: 42, uid: "TestUID", name: "Test", isInput: true, isOutput: false)
        
        // Then - id property should return the AudioDeviceID
        XCTAssertEqual(device.id, 42)
    }
}
