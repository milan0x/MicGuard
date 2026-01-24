//
//  OnAirSnoozeManager.swift
//  MicGuard
//
//  Manages ON AIR snooze timer and submenu
//

import Cocoa

class OnAirSnoozeManager {

    // MARK: - Properties

    private var preferencesManager: PreferencesManaging
    private weak var onAirSubmenu: NSMenu?
    private var snoozeTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    /// Called when snooze state changes, so the caller can refresh the ON AIR indicator
    var onSnoozeStateChanged: (() -> Void)?

    // MARK: - Initialization

    init(preferencesManager: PreferencesManaging, submenu: NSMenu?) {
        self.preferencesManager = preferencesManager
        self.onAirSubmenu = submenu

        // Check snooze expiry after system wake (Timer won't fire if system was asleep)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restorePersistedSnooze()
        }
    }

    deinit {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    func buildSubmenu(target: AnyObject,
                      toggleAction: Selector,
                      snoozeAction: Selector,
                      cancelAction: Selector) {
        guard let submenu = onAirSubmenu else { return }
        submenu.removeAllItems()

        let enableItem = NSMenuItem(
            title: "Show When Mic In Use",
            action: toggleAction,
            keyEquivalent: ""
        )
        enableItem.target = target
        enableItem.state = preferencesManager.showOnAirIndicator ? .on : .off
        submenu.addItem(enableItem)

        submenu.addItem(NSMenuItem.separator())

        let isEnabled = preferencesManager.showOnAirIndicator
        let isSnoozed = preferencesManager.isOnAirSnoozed

        let snooze1h = NSMenuItem(title: "Snooze for 1 Hour", action: snoozeAction, keyEquivalent: "")
        snooze1h.target = target
        snooze1h.tag = 1061
        snooze1h.isEnabled = isEnabled
        submenu.addItem(snooze1h)

        let snooze4h = NSMenuItem(title: "Snooze for 4 Hours", action: snoozeAction, keyEquivalent: "")
        snooze4h.target = target
        snooze4h.tag = 1062
        snooze4h.isEnabled = isEnabled
        submenu.addItem(snooze4h)

        let snoozeTomorrow = NSMenuItem(title: "Snooze Until Tomorrow", action: snoozeAction, keyEquivalent: "")
        snoozeTomorrow.target = target
        snoozeTomorrow.tag = 1063
        snoozeTomorrow.isEnabled = isEnabled
        submenu.addItem(snoozeTomorrow)

        if isSnoozed, let snoozeEnd = preferencesManager.onAirSnoozeUntil {
            submenu.addItem(NSMenuItem.separator())

            let formatter = DateFormatter()
            let calendar = Calendar.current
            if calendar.isDateInToday(snoozeEnd) {
                formatter.timeStyle = .short
                formatter.dateStyle = .none
            } else {
                formatter.timeStyle = .short
                formatter.dateStyle = .short
            }
            let statusItem = NSMenuItem(title: "Snoozed until \(formatter.string(from: snoozeEnd))", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            submenu.addItem(statusItem)

            let cancelItem = NSMenuItem(title: "Cancel Snooze", action: cancelAction, keyEquivalent: "")
            cancelItem.target = target
            submenu.addItem(cancelItem)
        }
    }

    func snooze(tag: Int) {
        let snoozeDate: Date
        switch tag {
        case 1061:
            snoozeDate = Date().addingTimeInterval(3600)
        case 1062:
            snoozeDate = Date().addingTimeInterval(4 * 3600)
        case 1063:
            let calendar = Calendar.current
            snoozeDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        default:
            return
        }

        preferencesManager.onAirSnoozeUntil = snoozeDate
        scheduleSnoozeExpiry()
        onSnoozeStateChanged?()
    }

    func cancelSnooze() {
        preferencesManager.onAirSnoozeUntil = nil
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        onSnoozeStateChanged?()
    }

    func scheduleSnoozeExpiry() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil

        guard let snoozeEnd = preferencesManager.onAirSnoozeUntil,
              snoozeEnd > Date() else { return }

        let timer = Timer(fire: snoozeEnd, interval: 0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.preferencesManager.onAirSnoozeUntil = nil
            self.snoozeTimer = nil
            self.onSnoozeStateChanged?()
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    func restorePersistedSnooze() {
        if let snoozeEnd = preferencesManager.onAirSnoozeUntil, snoozeEnd <= Date() {
            preferencesManager.onAirSnoozeUntil = nil
        } else {
            scheduleSnoozeExpiry()
        }
    }
}
