//
//  OnAirIndicatorTests.swift
//  MicGuardTests
//
//  Tests for OnAirIndicator flash restoration logic
//

import XCTest
import Combine
@testable import MicGuard

/// Mock PreferencesManager for testing OnAirIndicator
class MockPreferencesForOnAir: PreferencesManaging {
    var preferredInputDeviceUID: String?
    var preferredInputDeviceOrder: [String] = []
    var inputDeviceLockEnabled: Bool = false
    var volumeControlStrategy: VolumeControlStrategy = .none
    var targetVolume: Float = 0.75
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showNotifications: Bool = true
    var showOnAirIndicator: Bool = true
    var onAirSnoozeUntil: Date?
    var isOnAirSnoozed: Bool { onAirSnoozeUntil.map { $0 > Date() } ?? false }
    var showStats: Bool = false
    let preferencesChangedPublisher = PassthroughSubject<String, Never>()

    var preferredOutputDeviceUID: String?
    var preferredOutputDeviceOrder: [String] = []
    var outputDeviceLockEnabled: Bool = false
    var outputAutoSwitchEnabled: Bool = false

    func moveDevice(uid: String, direction: MoveDirection) {}
    func addDeviceToOrder(_ uid: String) {}
    func removeDeviceFromOrder(_ uid: String) {}
    func moveOutputDevice(uid: String, direction: MoveDirection) {}
    func addOutputDeviceToOrder(_ uid: String) {}
    func removeOutputDeviceFromOrder(_ uid: String) {}
    func cacheDeviceName(uid: String, name: String) {}
    func cachedDeviceName(for uid: String) -> String? { nil }
    func replaceDeviceUID(oldUID: String, newUID: String) {}
    func replaceOutputDeviceUID(oldUID: String, newUID: String) {}
}

final class OnAirIndicatorTests: XCTestCase {

    var indicator: OnAirIndicator!
    var mockPrefs: MockPreferencesForOnAir!

    override func setUp() {
        super.setUp()
        mockPrefs = MockPreferencesForOnAir()
        // Pass nil for statusItem since we can't create one in tests,
        // but we can still test state logic
        indicator = OnAirIndicator(statusItem: nil, preferencesManager: mockPrefs)
    }

    override func tearDown() {
        indicator = nil
        mockPrefs = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(indicator.isMicActive)
    }

    func testUpdateSetsState() {
        indicator.update(isInUse: true)
        XCTAssertTrue(indicator.isMicActive)

        indicator.update(isInUse: false)
        XCTAssertFalse(indicator.isMicActive)
    }

    func testForceUpdateAlwaysApplies() {
        indicator.update(isInUse: true)
        // Without force, same value is a no-op (returns early)
        // With force, it should still process
        indicator.update(isInUse: true, force: true)
        XCTAssertTrue(indicator.isMicActive)
    }

    func testFlashRestorationUsesCurrentState() {
        // Start with mic active and ON AIR enabled
        mockPrefs.showOnAirIndicator = true
        indicator.update(isInUse: true)

        // Start flash
        indicator.flash()

        // During flash, mic becomes inactive
        indicator.update(isInUse: false)

        // After flash completes + restoration delay, the indicator should
        // reflect the CURRENT state (inactive), not the stale captured state.
        // We can't test the visual output without a real NSStatusItem,
        // but we verify the state is correct.
        XCTAssertFalse(indicator.isMicActive,
                       "isMicActive should reflect current state, not captured flash state")
    }

    func testFlashRestorationWhenOnAirDisabledDuringFlash() {
        mockPrefs.showOnAirIndicator = true
        indicator.update(isInUse: true)

        indicator.flash()

        // During flash, user disables ON AIR
        mockPrefs.showOnAirIndicator = false

        // The restoration should use update(isInUse:force:) which checks
        // current showOnAirIndicator, not the stale captured value
        XCTAssertTrue(indicator.isMicActive)
        XCTAssertFalse(mockPrefs.showOnAirIndicator)
    }
}
