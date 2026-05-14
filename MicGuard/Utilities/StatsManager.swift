//
//  StatsManager.swift
//  MicGuard
//
//  Tracks app usage statistics locally
//

import Foundation
import Combine

// MARK: - Stat Types

enum StatType: String, CaseIterable {
    case hijacksBlocked = "HijacksBlocked"
    case outputHijacksBlocked = "OutputHijacksBlocked"
    case volumeCorrections = "VolumeCorrections"
    case volumeResets = "VolumeResets"

    var displayName: String {
        switch self {
        case .hijacksBlocked:
            return "Input Switches Blocked"
        case .outputHijacksBlocked:
            return "Output Switches Blocked"
        case .volumeCorrections:
            return "Volume Spikes Fixed"
        case .volumeResets:
            return "Post-Meeting Resets"
        }
    }
}

// MARK: - Protocol for Testability

protocol StatsManaging {
    func increment(stat: StatType)
    func get(stat: StatType) -> Int
    func getAll() -> [StatType: Int]
    func getTotal() -> Int
    func reset()
    
    var statsChangedPublisher: PassthroughSubject<StatType, Never> { get }
}

// MARK: - StatsManager Implementation

class StatsManager: StatsManaging {
    
    // MARK: - Singleton
    
    static let shared = StatsManager()
    
    // MARK: - Properties
    
    private let defaults: UserDefaults
    let statsChangedPublisher = PassthroughSubject<StatType, Never>()
    
    // MARK: - Initialization
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Public Methods
    
    func increment(stat: StatType) {
        let current = defaults.integer(forKey: stat.rawValue)
        defaults.set(current + 1, forKey: stat.rawValue)
        statsChangedPublisher.send(stat)
    }
    
    func get(stat: StatType) -> Int {
        return defaults.integer(forKey: stat.rawValue)
    }
    
    func getAll() -> [StatType: Int] {
        var stats: [StatType: Int] = [:]
        for stat in StatType.allCases {
            stats[stat] = get(stat: stat)
        }
        return stats
    }
    
    func getTotal() -> Int {
        return StatType.allCases.reduce(0) { $0 + get(stat: $1) }
    }
    
    func reset() {
        for stat in StatType.allCases {
            defaults.set(0, forKey: stat.rawValue)
            statsChangedPublisher.send(stat)
        }
    }
    
    // MARK: - Formatted Output
    
    func getReport() -> String {
        let total = getTotal()
        return "🛡️ MicGuard has saved your settings \(total) times."
    }
    
    func getDetailedReport() -> String {
        var lines: [String] = ["MicGuard Stats:"]
        
        for stat in StatType.allCases {
            let count = get(stat: stat)
            lines.append("   \(count) \(stat.displayName)")
        }
        
        return lines.joined(separator: "\n")
    }
}
