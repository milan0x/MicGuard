//
//  ProcessMonitorTests.swift
//  MicGuardTests
//
//  Tests for ProcessMonitor functionality
//

import XCTest
@testable import MicGuard

final class ProcessMonitorTests: XCTestCase {

    var processMonitor: ProcessMonitor!

    override func setUp() {
        super.setUp()
        processMonitor = ProcessMonitor()
    }

    override func tearDown() {
        processMonitor = nil
        super.tearDown()
    }

    // MARK: - isBrowserProcess Tests

    func testIsBrowserProcessWithChrome() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.google.Chrome"))
    }

    func testIsBrowserProcessWithChromeCanary() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.google.Chrome.canary"))
    }

    func testIsBrowserProcessWithSafari() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.apple.Safari"))
    }

    func testIsBrowserProcessWithFirefox() {
        XCTAssertTrue(processMonitor.isBrowserProcess("org.mozilla.firefox"))
    }

    func testIsBrowserProcessWithEdge() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.microsoft.edgemac"))
    }

    func testIsBrowserProcessWithBrave() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.brave.Browser"))
    }

    func testIsBrowserProcessWithArc() {
        XCTAssertTrue(processMonitor.isBrowserProcess("company.thebrowser.Browser"))
    }

    func testIsBrowserProcessWithVivaldi() {
        XCTAssertTrue(processMonitor.isBrowserProcess("com.vivaldi.Vivaldi"))
    }

    func testIsBrowserProcessReturnsFalseForZoom() {
        XCTAssertFalse(processMonitor.isBrowserProcess("us.zoom.xos"))
    }

    func testIsBrowserProcessReturnsFalseForSlack() {
        XCTAssertFalse(processMonitor.isBrowserProcess("com.tinyspeck.slackmacgap"))
    }

    func testIsBrowserProcessReturnsFalseForFinder() {
        XCTAssertFalse(processMonitor.isBrowserProcess("com.apple.finder"))
    }

    func testIsBrowserProcessReturnsFalseForUnknownApp() {
        XCTAssertFalse(processMonitor.isBrowserProcess("com.example.unknownapp"))
    }

    // MARK: - isKnownAudioApp Tests

    func testIsKnownAudioAppWithZoom() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("us.zoom.xos"))
    }

    func testIsKnownAudioAppWithDiscord() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.discord"))
    }

    func testIsKnownAudioAppWithTeams() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.microsoft.teams"))
    }

    func testIsKnownAudioAppWithTeams2() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.microsoft.teams2"))
    }

    func testIsKnownAudioAppWithSlack() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.tinyspeck.slackmacgap"))
    }

    func testIsKnownAudioAppWithFaceTime() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.apple.FaceTime"))
    }

    func testIsKnownAudioAppWithOBS() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("com.obsproject.obs-studio"))
    }

    func testIsKnownAudioAppWithLoom() {
        XCTAssertTrue(processMonitor.isKnownAudioApp("us.loom.desktop"))
    }

    func testIsKnownAudioAppReturnsFalseForBrowser() {
        XCTAssertFalse(processMonitor.isKnownAudioApp("com.google.Chrome"))
    }

    func testIsKnownAudioAppReturnsFalseForUnknown() {
        XCTAssertFalse(processMonitor.isKnownAudioApp("com.example.randomapp"))
    }
}
