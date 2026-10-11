//
//  PopoverViewModelTests.swift
//  MicGuardTests
//
//  Device-list resolution: auto-append, default exclusions, hide-virtual filter.
//

import XCTest
import CoreAudio
@testable import MicGuard

@MainActor
final class PopoverViewModelTests: XCTestCase {

    private let suite = "com.micguard.tests.popover"
    private var defaults: UserDefaults!
    private var audio: MockAudioDeviceManager!
    private var prefs: PreferencesManager!
    private var stats: StatsManager!

    private let builtIn = AudioDevice(id: 1, uid: "builtin", name: "MacBook Pro Microphone",
                                      isInput: true, isOutput: false,
                                      transportType: kAudioDeviceTransportTypeBuiltIn)
    private let iphone = AudioDevice(id: 2, uid: "iphone", name: "iPhone Microphone",
                                     isInput: true, isOutput: false,
                                     transportType: kAudioDeviceTransportTypeContinuityCaptureWireless)
    private let usb = AudioDevice(id: 3, uid: "usb", name: "Shure MV7",
                                  isInput: true, isOutput: false,
                                  transportType: kAudioDeviceTransportTypeUSB)
    private let loopback = AudioDevice(id: 4, uid: "blackhole", name: "BlackHole 2ch",
                                       isInput: true, isOutput: true,
                                       transportType: kAudioDeviceTransportTypeVirtual)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        audio = MockAudioDeviceManager()
        prefs = PreferencesManager(defaults: defaults)
        stats = StatsManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let login = StubLaunchAtLogin()

    private func makeViewModel() -> PopoverViewModel {
        PopoverViewModel(audioDeviceManager: audio, preferencesManager: prefs,
                         statsManager: stats, activityMonitor: nil,
                         launchAtLoginProvider: login)
    }

    // MARK: Launch at login

    func testLaunchAtLoginToggleReflectsSystemNotPreference() {
        prefs.launchAtLogin = true          // stale intent from a failed registration
        login.isEnabled = false
        let vm = makeViewModel()
        XCTAssertFalse(vm.launchAtLogin, "Toggle must show what is registered, not the stored intent")
    }

    func testLaunchAtLoginSuccessUpdatesToggleAndIntent() {
        let vm = makeViewModel()
        vm.setLaunchAtLogin(true)
        XCTAssertEqual(login.calls, [true])
        XCTAssertTrue(vm.launchAtLogin)
        XCTAssertTrue(prefs.launchAtLogin)
    }

    func testLaunchAtLoginFailureSnapsToggleBack() {
        login.shouldFail = true
        let vm = makeViewModel()
        vm.setLaunchAtLogin(true)
        XCTAssertFalse(vm.launchAtLogin, "System refused — toggle must not stay on")
        XCTAssertFalse(prefs.launchAtLogin, "Intent follows reality, no phantom on")
    }

    func testLaunchAtLoginRequiresApprovalShowsOnWithHint() {
        login.requiresApproval = true
        let vm = makeViewModel()
        XCTAssertTrue(vm.launchAtLogin)
        XCTAssertTrue(vm.launchAtLoginNeedsApproval)
    }

    func testFirstSightingOfContinuityMicIsExcludedFromAutoSelection() {
        audio.inputDevices = [builtIn, iphone]
        audio.setDefaultInputDevice(builtIn)

        let vm = makeViewModel()

        XCTAssertEqual(prefs.preferredInputDeviceOrder, ["builtin", "iphone"], "Both devices auto-appended")
        XCTAssertTrue(prefs.isInputDeviceExcluded("iphone"), "iPhone mic must start excluded")
        XCTAssertFalse(prefs.isInputDeviceExcluded("builtin"))
        XCTAssertEqual(vm.inputDevices.map(\.isExcluded), [false, true])
        XCTAssertEqual(vm.preferredInputDisplayName, "MacBook Pro Microphone")
    }

    func testExcludedDeviceIsSkippedForPreferredNameButStaysListed() {
        audio.inputDevices = [builtIn, iphone]
        audio.setDefaultInputDevice(builtIn)
        let vm = makeViewModel()

        vm.setInputDeviceExcluded(at: 0, excluded: true)   // exclude built-in too

        XCTAssertEqual(vm.inputDevices.count, 2, "Exclusion never removes a row")
        XCTAssertNil(vm.preferredInputDisplayName, "Nothing auto-selectable → no preferred name")

        vm.setInputDeviceExcluded(at: 1, excluded: false)
        XCTAssertEqual(vm.preferredInputDisplayName, "iPhone Microphone")
    }

    func testUsingAnExcludedDeviceClearsItsExclusion() {
        audio.inputDevices = [builtIn, iphone]
        audio.setDefaultInputDevice(builtIn)
        let vm = makeViewModel()
        XCTAssertTrue(prefs.isInputDeviceExcluded("iphone"))

        vm.useInputDevice(at: 1)

        XCTAssertEqual(audio.defaultInputDevice?.uid, "iphone")
        XCTAssertEqual(prefs.preferredInputDeviceOrder.first, "iphone")
        XCTAssertFalse(prefs.isInputDeviceExcluded("iphone"),
                       "A deliberate pick must re-allow the device or the lock would bounce off it")
    }

    func testExclusionIsNotReappliedOnceTheUserAllowsADevice() {
        audio.inputDevices = [builtIn, iphone]
        audio.setDefaultInputDevice(builtIn)
        let vm = makeViewModel()
        vm.setInputDeviceExcluded(at: 1, excluded: false)

        // Device churn re-resolves the list; the iPhone is no longer "new".
        audio.devicesChangedPublisher.send()
        let wait = XCTestExpectation(description: "main hop")
        DispatchQueue.main.async { wait.fulfill() }
        self.wait(for: [wait], timeout: 1)

        XCTAssertFalse(prefs.isInputDeviceExcluded("iphone"))
    }

    func testUpgradeExcludesAlreadyListedContinuityMic() {
        // Pre-exclusion install: iPhone already sits in the saved order, so it is
        // not "new" — the rule must still apply the first time it is seen.
        prefs.preferredInputDeviceOrder = ["builtin", "iphone"]
        audio.inputDevices = [builtIn, iphone]
        audio.setDefaultInputDevice(builtIn)

        _ = makeViewModel()

        XCTAssertTrue(prefs.isInputDeviceExcluded("iphone"), "Existing iPhone entry excluded on first sighting")

        // User allows it deliberately; later refreshes must not re-exclude.
        prefs.setInputDeviceExcluded(false, uid: "iphone")
        let vm = makeViewModel()
        XCTAssertFalse(prefs.isInputDeviceExcluded("iphone"))
        XCTAssertEqual(vm.inputDevices.map(\.isExcluded), [false, false])
    }

    func testListedButDisconnectedIPhoneIsExcludedByCachedName() {
        // Upgrade while the phone is away: transport unknown, cached name decides.
        prefs.preferredInputDeviceOrder = ["builtin", "iphone"]
        prefs.cacheDeviceName(uid: "iphone", name: "Milan’s iPhone Microphone")
        audio.inputDevices = [builtIn]
        audio.setDefaultInputDevice(builtIn)

        _ = makeViewModel()

        XCTAssertTrue(prefs.isInputDeviceExcluded("iphone"))
        XCTAssertFalse(prefs.isInputDeviceExcluded("builtin"))
    }

    func testRuleWaitsUntilThePhoneActuallyAppears() {
        // Upgrade while the phone is away and no cached name: nothing to
        // evaluate yet, no marker burned.
        prefs.preferredInputDeviceOrder = ["builtin", "iphone"]
        audio.inputDevices = [builtIn]
        audio.setDefaultInputDevice(builtIn)
        let vm = makeViewModel()
        XCTAssertFalse(prefs.isInputDeviceExcluded("iphone"))

        // Phone comes into range later.
        audio.inputDevices = [builtIn, iphone]
        audio.devicesChangedPublisher.send()
        let hop = XCTestExpectation(description: "main hop")
        DispatchQueue.main.async { hop.fulfill() }
        wait(for: [hop], timeout: 1)

        XCTAssertTrue(prefs.isInputDeviceExcluded("iphone"), "Excluded the first time it is seen connected")
        XCTAssertEqual(vm.inputDevices.map(\.isExcluded), [false, true])
    }

    func testHideVirtualKeepsRuntimeRejectedRealDeviceVisible() {
        audio.inputDevices = [builtIn, usb, loopback]
        audio.setDefaultInputDevice(builtIn)
        audio.silentlyRefusedUIDs = ["usb"]   // macOS refuses the set this session
        prefs.hideVirtualDevices = true
        let vm = makeViewModel()

        XCTAssertEqual(vm.inputDevices.map(\.id), ["builtin", "usb"], "Loopback hidden, real mic shown")

        vm.useInputDevice(at: 1)   // rejected → flagged unsettable

        XCTAssertEqual(vm.inputDevices.map(\.id), ["builtin", "usb"],
                       "A refused real device must not vanish behind the virtual filter")
        XCTAssertTrue(vm.inputDevices[1].unsettable)
        XCTAssertFalse(vm.inputDevices[1].isVirtual)
    }
}

private final class StubLaunchAtLogin: LaunchAtLoginProviding {
    var isEnabled = false
    var requiresApproval = false
    var shouldFail = false
    var calls: [Bool] = []
    var openedSettings = false

    func setLaunchAtLogin(enabled: Bool) -> Bool {
        calls.append(enabled)
        if shouldFail { return false }
        isEnabled = enabled
        return true
    }

    func openSystemSettings() { openedSettings = true }
}
