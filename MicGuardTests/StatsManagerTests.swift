//
//  StatsManagerTests.swift
//  MicGuardTests
//
//  Tests for StatsManager functionality
//

import XCTest
import Combine
@testable import MicGuard

final class StatsManagerTests: XCTestCase {
    
    var statsManager: StatsManager!
    var testDefaults: UserDefaults!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        // Use a separate UserDefaults suite for testing
        testDefaults = UserDefaults(suiteName: "com.micguard.stats.tests")!
        testDefaults.removePersistentDomain(forName: "com.micguard.stats.tests")
        
        statsManager = StatsManager(defaults: testDefaults)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.micguard.stats.tests")
        testDefaults = nil
        statsManager = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialStatsAreZero() {
        XCTAssertEqual(statsManager.get(stat: .hijacksBlocked), 0)
        XCTAssertEqual(statsManager.get(stat: .volumeCorrections), 0)
        XCTAssertEqual(statsManager.get(stat: .volumeResets), 0)
        XCTAssertEqual(statsManager.getTotal(), 0)
    }
    
    // MARK: - Increment Tests
    
    func testIncrementHijacksBlocked() {
        // When
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .hijacksBlocked)
        
        // Then
        XCTAssertEqual(statsManager.get(stat: .hijacksBlocked), 3)
    }
    
    func testIncrementVolumeCorrections() {
        // When
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeCorrections)
        
        // Then
        XCTAssertEqual(statsManager.get(stat: .volumeCorrections), 2)
    }
    
    func testIncrementVolumeResets() {
        // When
        statsManager.increment(stat: .volumeResets)
        
        // Then
        XCTAssertEqual(statsManager.get(stat: .volumeResets), 1)
    }
    
    // MARK: - Total Tests
    
    func testGetTotal() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeResets)
        
        // Then
        XCTAssertEqual(statsManager.getTotal(), 6)
    }
    
    // MARK: - GetAll Tests
    
    func testGetAll() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeCorrections)
        
        // When
        let allStats = statsManager.getAll()
        
        // Then
        XCTAssertEqual(allStats[.hijacksBlocked], 1)
        XCTAssertEqual(allStats[.volumeCorrections], 2)
        XCTAssertEqual(allStats[.volumeResets], 0)
    }
    
    // MARK: - Reset Tests
    
    func testReset() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeResets)
        
        // When
        statsManager.reset()
        
        // Then
        XCTAssertEqual(statsManager.get(stat: .hijacksBlocked), 0)
        XCTAssertEqual(statsManager.get(stat: .volumeCorrections), 0)
        XCTAssertEqual(statsManager.get(stat: .volumeResets), 0)
        XCTAssertEqual(statsManager.getTotal(), 0)
    }
    
    // MARK: - Persistence Tests
    
    func testStatsPersistToUserDefaults() {
        // When
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        
        // Then
        XCTAssertEqual(testDefaults.integer(forKey: "HijacksBlocked"), 1)
        XCTAssertEqual(testDefaults.integer(forKey: "VolumeCorrections"), 1)
    }
    
    // MARK: - Report Tests
    
    func testGetReport() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        statsManager.increment(stat: .volumeResets)
        
        // When
        let report = statsManager.getReport()
        
        // Then
        XCTAssertEqual(report, "🛡️ MicGuard has saved your settings 3 times.")
    }
    
    func testGetDetailedReport() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .hijacksBlocked)
        statsManager.increment(stat: .volumeCorrections)
        
        // When
        let report = statsManager.getDetailedReport()
        
        // Then (no emojis, just count and name)
        XCTAssertTrue(report.contains("2 Input Switches Blocked"))
        XCTAssertTrue(report.contains("1 Volume Spikes Fixed"))
        XCTAssertTrue(report.contains("0 Post-Meeting Resets"))
    }
    
    // MARK: - Publisher Tests
    
    func testStatsChangedPublisher() {
        // Given
        let expectation = XCTestExpectation(description: "Stats changed publisher")
        var receivedStat: StatType?
        
        statsManager.statsChangedPublisher
            .sink { stat in
                receivedStat = stat
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When
        statsManager.increment(stat: .hijacksBlocked)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStat, .hijacksBlocked)
    }
    
    func testStatsChangedPublisherOnReset() {
        // Given
        statsManager.increment(stat: .hijacksBlocked)
        
        var receivedStats: [StatType] = []
        let expectation = XCTestExpectation(description: "Reset publishes all stats")
        expectation.expectedFulfillmentCount = StatType.allCases.count

        statsManager.statsChangedPublisher
            .sink { stat in
                receivedStats.append(stat)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        statsManager.reset()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStats.count, StatType.allCases.count)
        XCTAssertTrue(receivedStats.contains(.hijacksBlocked))
        XCTAssertTrue(receivedStats.contains(.outputHijacksBlocked))
        XCTAssertTrue(receivedStats.contains(.volumeCorrections))
        XCTAssertTrue(receivedStats.contains(.volumeResets))
    }

    // MARK: - StatType Tests

    func testStatTypeDisplayNames() {
        XCTAssertEqual(StatType.hijacksBlocked.displayName, "Input Switches Blocked")
        XCTAssertEqual(StatType.outputHijacksBlocked.displayName, "Output Switches Blocked")
        XCTAssertEqual(StatType.volumeCorrections.displayName, "Volume Spikes Fixed")
        XCTAssertEqual(StatType.volumeResets.displayName, "Post-Meeting Resets")
    }
    
}
