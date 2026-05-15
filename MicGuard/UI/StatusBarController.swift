//
//  StatusBarController.swift
//  MicGuard
//
//  Manages the menu bar icon and dropdown menu
//

import Cocoa
import Combine

class StatusBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private let audioDeviceManager: AudioDeviceManaging
    private let preferencesManager: PreferencesManaging
    private let statsManager: StatsManaging
    private var activityMonitor: ActivityMonitor?

    private var cancellables = Set<AnyCancellable>()

    // Menu item references for dynamic updates
    private var statusMenuItem: NSMenuItem?
    private var lockStatusMenuItem: NSMenuItem?
    private var lockToggleMenuItem: NSMenuItem?
    private var inputDeviceMenuItem: NSMenuItem?
    private var inputDeviceSubmenu: NSMenu?
    private var outputDeviceMenuItem: NSMenuItem?
    private var outputDeviceSubmenu: NSMenu?
    private var volumeSliderItem: NSMenuItem?
    private var statsMenuItems: [NSMenuItem] = []

    // Extracted components
    private var onAirIndicator: OnAirIndicator?
    private var snoozeManager: OnAirSnoozeManager?
    private var deviceSubmenuBuilder: DeviceSubmenuBuilder?
    private var outputDeviceSubmenuBuilder: OutputDeviceSubmenuBuilder?
    private var onAirSubmenu: NSMenu?

    // MARK: - Initialization

    init(audioDeviceManager: AudioDeviceManaging,
         preferencesManager: PreferencesManaging,
         statsManager: StatsManaging,
         activityMonitor: ActivityMonitor?) {
        self.audioDeviceManager = audioDeviceManager
        self.preferencesManager = preferencesManager
        self.statsManager = statsManager
        self.activityMonitor = activityMonitor

        setupStatusItem()
        setupMenu()
        setupObservers()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "MicGuard")
            button.image?.isTemplate = true
        }

        onAirIndicator = OnAirIndicator(statusItem: statusItem, preferencesManager: preferencesManager)
    }

    private func setupMenu() {
        menu = NSMenu()

        // Status display with device name and live input level
        statusMenuItem = NSMenuItem(title: "Mic: --", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu?.addItem(statusMenuItem!)

        // Lock status line — always visible so the user can tell at a glance whether
        // MicGuard is actively protecting the input device. Disabled (informational only).
        lockStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lockStatusMenuItem?.isEnabled = false
        menu?.addItem(lockStatusMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // Input Settings Section
        let inputHeader = MenuItemFactory.createSectionHeader(title: "Input Settings")
        menu?.addItem(inputHeader)

        // Lock Input Device toggle — title reflects state so the action is obvious.
        let lockInputItem = NSMenuItem(
            title: "",
            action: #selector(toggleInputDeviceLock),
            keyEquivalent: ""
        )
        lockInputItem.target = self
        lockInputItem.state = preferencesManager.inputDeviceLockEnabled ? .on : .off
        lockInputItem.tag = 100
        menu?.addItem(lockInputItem)
        lockToggleMenuItem = lockInputItem
        updateLockToggleTitle()
        updateLockStatusDisplay()

        // Input device submenu
        inputDeviceMenuItem = NSMenuItem(title: "    Select Device", action: nil, keyEquivalent: "")
        inputDeviceSubmenu = NSMenu()
        inputDeviceMenuItem?.submenu = inputDeviceSubmenu
        menu?.addItem(inputDeviceMenuItem!)

        deviceSubmenuBuilder = DeviceSubmenuBuilder(
            audioDeviceManager: audioDeviceManager,
            preferencesManager: preferencesManager,
            submenu: inputDeviceSubmenu
        )
        updateInputDeviceSubmenu()
        updateInputDeviceMenuItemTitle()

        menu?.addItem(NSMenuItem.separator())

        // Volume Control Strategy Section
        let volumeHeader = MenuItemFactory.createSectionHeader(title: "Volume Control")
        menu?.addItem(volumeHeader)

        let currentStrategy = preferencesManager.volumeControlStrategy

        // Strategy: None
        let noneItem = NSMenuItem(
            title: "None",
            action: #selector(selectVolumeStrategy),
            keyEquivalent: ""
        )
        noneItem.target = self
        noneItem.state = currentStrategy == .none ? .on : .off
        noneItem.tag = 300
        menu?.addItem(noneItem)

        // Strategy: Lock Volume
        let lockItem = NSMenuItem(
            title: "",
            action: #selector(selectVolumeStrategy),
            keyEquivalent: ""
        )
        let lockTitle = NSMutableAttributedString(
            string: "Lock Input Volume ",
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        lockTitle.append(NSAttributedString(
            string: "(Continuous Protection)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        lockItem.attributedTitle = lockTitle
        lockItem.target = self
        lockItem.state = currentStrategy == .lockVolume ? .on : .off
        lockItem.tag = 301
        menu?.addItem(lockItem)

        // Strategy: Reset When Mic Not In Use (recommended)
        let resetItem = NSMenuItem(
            title: "",
            action: #selector(selectVolumeStrategy),
            keyEquivalent: ""
        )
        let resetTitle = NSMutableAttributedString(
            string: "Reset When Mic Not In Use ",
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        resetTitle.append(NSAttributedString(
            string: "(Recommended)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        resetItem.attributedTitle = resetTitle
        resetItem.target = self
        resetItem.state = currentStrategy == .resetWhenMicStops ? .on : .off
        resetItem.tag = 302
        menu?.addItem(resetItem)

        // Single target volume slider (only shown if strategy != none)
        if currentStrategy != .none {
            volumeSliderItem = MenuItemFactory.createVolumeSliderItem(
                value: preferencesManager.targetVolume,
                target: self,
                action: #selector(targetVolumeChanged(_:)),
                tag: 200
            )
            menu?.addItem(volumeSliderItem!)
        }

        menu?.addItem(NSMenuItem.separator())

        // Output Settings Section
        let outputHeader = MenuItemFactory.createSectionHeader(title: "Output Settings")
        menu?.addItem(outputHeader)

        // Lock Output Device
        let lockOutputItem = NSMenuItem(
            title: "Lock Output Device",
            action: #selector(toggleOutputDeviceLock),
            keyEquivalent: ""
        )
        lockOutputItem.target = self
        lockOutputItem.state = preferencesManager.outputDeviceLockEnabled ? .on : .off
        lockOutputItem.tag = 150
        menu?.addItem(lockOutputItem)

        // Auto-switch output on connect
        let autoSwitchItem = NSMenuItem(
            title: "",
            action: #selector(toggleOutputAutoSwitch),
            keyEquivalent: ""
        )
        let autoSwitchTitle = NSMutableAttributedString(
            string: "Auto-Switch on Connect ",
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        autoSwitchTitle.append(NSAttributedString(
            string: "(Switch when device appears)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        autoSwitchItem.attributedTitle = autoSwitchTitle
        autoSwitchItem.target = self
        autoSwitchItem.state = preferencesManager.outputAutoSwitchEnabled ? .on : .off
        autoSwitchItem.tag = 151
        menu?.addItem(autoSwitchItem)

        // Output device submenu
        outputDeviceMenuItem = NSMenuItem(title: "    Select Device", action: nil, keyEquivalent: "")
        outputDeviceSubmenu = NSMenu()
        outputDeviceMenuItem?.submenu = outputDeviceSubmenu
        menu?.addItem(outputDeviceMenuItem!)

        outputDeviceSubmenuBuilder = OutputDeviceSubmenuBuilder(
            audioDeviceManager: audioDeviceManager,
            preferencesManager: preferencesManager,
            submenu: outputDeviceSubmenu
        )
        updateOutputDeviceSubmenu()
        updateOutputDeviceMenuItemTitle()

        menu?.addItem(NSMenuItem.separator())

        // App Settings Section
        let settingsHeader = MenuItemFactory.createSectionHeader(title: "Settings")
        menu?.addItem(settingsHeader)

        // Launch at Login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = preferencesManager.launchAtLogin ? .on : .off
        launchItem.tag = 104
        menu?.addItem(launchItem)

        // Show Notifications
        let notifyItem = NSMenuItem(
            title: "Show Notifications",
            action: #selector(toggleNotifications),
            keyEquivalent: ""
        )
        notifyItem.target = self
        notifyItem.state = preferencesManager.showNotifications ? .on : .off
        notifyItem.tag = 105
        menu?.addItem(notifyItem)

        // ON AIR Indicator with submenu
        let onAirItem = NSMenuItem(
            title: "ON AIR Indicator",
            action: nil,
            keyEquivalent: ""
        )
        onAirItem.tag = 106
        let submenu = NSMenu()
        onAirItem.submenu = submenu
        self.onAirSubmenu = submenu
        menu?.addItem(onAirItem)

        snoozeManager = OnAirSnoozeManager(preferencesManager: preferencesManager, submenu: submenu)
        snoozeManager?.onSnoozeStateChanged = { [weak self] in
            self?.refreshSnoozeUI()
        }
        buildOnAirSubmenu()

        // Show Stats
        let showStatsItem = NSMenuItem(
            title: "Show Stats",
            action: #selector(toggleShowStats),
            keyEquivalent: ""
        )
        showStatsItem.target = self
        showStatsItem.state = preferencesManager.showStats ? .on : .off
        showStatsItem.tag = 107
        menu?.addItem(showStatsItem)

        menu?.addItem(NSMenuItem.separator())

        // Stats Section (conditionally shown)
        if preferencesManager.showStats {
            let statsHeader = MenuItemFactory.createSectionHeader(title: "MicGuard Stats")
            statsHeader.tag = 499
            menu?.addItem(statsHeader)

            for stat in StatType.allCases {
                let count = statsManager.get(stat: stat)
                let statItem = NSMenuItem(
                    title: "\(count) \(stat.displayName)",
                    action: nil,
                    keyEquivalent: ""
                )
                statItem.tag = 500 + StatType.allCases.firstIndex(of: stat)!
                statsMenuItems.append(statItem)
                menu?.addItem(statItem)
            }

            let resetStatsItem = NSMenuItem(
                title: "Reset Stats...",
                action: #selector(resetStats),
                keyEquivalent: ""
            )
            resetStatsItem.target = self
            resetStatsItem.tag = 510
            menu?.addItem(resetStatsItem)

            menu?.addItem(NSMenuItem.separator())
        }

        // About
        let aboutItem = NSMenuItem(
            title: "About MicGuard",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu?.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MicGuard",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupObservers() {
        // Update input level display
        activityMonitor?.inputLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateInputLevelDisplay(level: level)
            }
            .store(in: &cancellables)

        // Update menu when devices change
        audioDeviceManager.devicesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateInputDeviceSubmenu()
                self?.updateOutputDeviceSubmenu()
                self?.updateStatusDisplay()
            }
            .store(in: &cancellables)

        // Update status when default input device changes
        audioDeviceManager.defaultInputChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusDisplay()
                self?.updateInputDeviceMenuItemTitle()
                self?.updateInputDeviceSubmenu()
                self?.updateLockStatusDisplay()
            }
            .store(in: &cancellables)

        // Update status when preferred input device changes
        NotificationCenter.default.publisher(for: .preferredInputDeviceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusDisplay()
                self?.updateInputDeviceMenuItemTitle()
                self?.updateInputDeviceSubmenu()
                self?.updateLockStatusDisplay()
            }
            .store(in: &cancellables)

        // Also rebuild the submenu when the device list changes, so newly-connected devices
        // appear immediately rather than only after the next default-change event.
        audioDeviceManager.devicesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateInputDeviceSubmenu()
                self?.updateInputDeviceMenuItemTitle()
                self?.updateLockStatusDisplay()
            }
            .store(in: &cancellables)

        // Update when default output device changes
        audioDeviceManager.defaultOutputChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOutputDeviceSubmenu()
                self?.updateOutputDeviceMenuItemTitle()
            }
            .store(in: &cancellables)

        // Update when preferred output device changes
        NotificationCenter.default.publisher(for: .preferredOutputDeviceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateOutputDeviceSubmenu()
                self?.updateOutputDeviceMenuItemTitle()
            }
            .store(in: &cancellables)

        // Update stats display
        statsManager.statsChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stat in
                self?.updateStatsDisplay(for: stat)
            }
            .store(in: &cancellables)

        // Update ON AIR indicator based on mic in use state
        activityMonitor?.micInUsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInUse in
                self?.onAirIndicator?.update(isInUse: isInUse)
            }
            .store(in: &cancellables)

        // Check initial ON AIR state
        let initialInUse = activityMonitor?.isMicrophoneInUse ?? false
        onAirIndicator?.update(isInUse: initialInUse, force: true)

        // Restore persisted snooze timer
        snoozeManager?.restorePersistedSnooze()

        // Initial status display update
        updateStatusDisplay()
    }

    // MARK: - Public Methods

    func flashOnAirIndicator() {
        onAirIndicator?.flash()
    }

    // MARK: - Menu Updates

    private func currentDisplayDevice() -> AudioDevice? {
        // Show the actual active system default so the status reflects reality.
        // If we showed the preferred device instead, a failed lock would be hidden behind a
        // status line that disagrees with the submenu's checkmark.
        return audioDeviceManager.defaultInputDevice
    }

    private func updateInputLevelDisplay(level: Float) {
        guard let device = currentDisplayDevice() else {
            statusMenuItem?.title = "No Microphone"
            return
        }

        let percentage = Int(level * 100)
        statusMenuItem?.title = "\(device.name) (\(percentage)%)"
    }

    private func updateStatusDisplay() {
        guard let device = currentDisplayDevice() else {
            statusMenuItem?.title = "No Microphone"
            return
        }

        statusMenuItem?.title = "\(device.name) (0%)"
    }

    private func updateInputDeviceSubmenu() {
        deviceSubmenuBuilder?.updateSubmenu(
            target: self,
            moveUpAction: #selector(moveDeviceUp(_:)),
            moveDownAction: #selector(moveDeviceDown(_:)),
            removeAction: #selector(removeDevice(_:)),
            useAction: #selector(useInputDevice(_:))
        )
    }

    private func updateOutputDeviceSubmenu() {
        outputDeviceSubmenuBuilder?.updateSubmenu(
            target: self,
            moveUpAction: #selector(moveOutputDeviceUp(_:)),
            moveDownAction: #selector(moveOutputDeviceDown(_:)),
            removeAction: #selector(removeOutputDevice(_:)),
            useAction: #selector(useOutputDevice(_:))
        )
    }

    private func updateOutputDeviceMenuItemTitle() {
        let preferredUID = preferencesManager.preferredOutputDeviceUID

        if let uid = preferredUID,
           let device = audioDeviceManager.device(forUID: uid) {
            outputDeviceMenuItem?.title = "    Device: \(device.name)"
        } else if let defaultDevice = audioDeviceManager.defaultOutputDevice {
            outputDeviceMenuItem?.title = "    Device: \(defaultDevice.name)"
        } else {
            outputDeviceMenuItem?.title = "    Select Device"
        }
    }

    private func updateInputDeviceMenuItemTitle() {
        // Show the actual active device so this stays consistent with the submenu's checkmark
        // and the top status line. Previously this showed the preferred device, which hid
        // lock failures behind a name that didn't match reality.
        if let defaultDevice = audioDeviceManager.defaultInputDevice {
            inputDeviceMenuItem?.title = "    Device: \(defaultDevice.name)"
        } else {
            inputDeviceMenuItem?.title = "    Select Device"
        }
    }

    private func updateLockStatusDisplay() {
        guard let item = lockStatusMenuItem else { return }
        if preferencesManager.inputDeviceLockEnabled {
            let deviceName = preferredDeviceDisplayName() ?? "preferred device"
            item.title = "🔒 Locked to \(deviceName)"
        } else {
            item.title = "🔓 No lock — devices may auto-switch"
        }
    }

    private func updateLockToggleTitle() {
        guard let item = lockToggleMenuItem else { return }
        if preferencesManager.inputDeviceLockEnabled {
            item.title = "🔒 Lock ON"
        } else {
            item.title = "⚠️ Lock OFF — Click to Enable"
        }
    }

    /// First available device in the priority list (or its cached name if disconnected).
    /// Used in the lock status line so the user sees what the lock is protecting.
    private func preferredDeviceDisplayName() -> String? {
        for uid in preferencesManager.preferredInputDeviceOrder {
            if let device = audioDeviceManager.device(forUID: uid) {
                return device.name
            }
            if let name = preferencesManager.cachedDeviceName(for: uid) {
                return name
            }
        }
        return nil
    }

    private func updateStatsDisplay(for stat: StatType) {
        guard let index = StatType.allCases.firstIndex(of: stat),
              index < statsMenuItems.count else { return }

        let count = statsManager.get(stat: stat)
        statsMenuItems[index].title = "\(count) \(stat.displayName)"
    }

    private func buildOnAirSubmenu() {
        snoozeManager?.buildSubmenu(
            target: self,
            toggleAction: #selector(toggleOnAirIndicator),
            snoozeAction: #selector(snoozeOnAir(_:)),
            cancelAction: #selector(cancelOnAirSnooze)
        )
    }

    private func refreshSnoozeUI() {
        buildOnAirSubmenu()
        let isInUse = activityMonitor?.isMicrophoneInUse ?? false
        onAirIndicator?.update(isInUse: isInUse, force: true)
    }

    // MARK: - Actions

    @objc private func toggleInputDeviceLock(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.inputDeviceLockEnabled = isEnabled
        NSLog("[MicGuard.UI] toggleInputDeviceLock: wrote \(isEnabled), readback=\(preferencesManager.inputDeviceLockEnabled)")

        updateLockToggleTitle()
        updateLockStatusDisplay()

        NotificationCenter.default.post(name: .inputDeviceLockChanged, object: nil)
    }

    @objc private func selectVolumeStrategy(_ sender: NSMenuItem) {
        let strategy: VolumeControlStrategy
        switch sender.tag {
        case 300: strategy = .none
        case 301: strategy = .lockVolume
        case 302: strategy = .resetWhenMicStops
        default: return
        }

        preferencesManager.volumeControlStrategy = strategy

        setupMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.launchAtLogin = isEnabled
    }

    @objc private func toggleNotifications(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.showNotifications = isEnabled
    }

    @objc private func toggleOnAirIndicator(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.showOnAirIndicator = isEnabled

        if !isEnabled {
            snoozeManager?.cancelSnooze()
        }

        buildOnAirSubmenu()

        let isInUse = activityMonitor?.isMicrophoneInUse ?? false
        onAirIndicator?.update(isInUse: isInUse, force: true)
    }

    @objc private func snoozeOnAir(_ sender: NSMenuItem) {
        snoozeManager?.snooze(tag: sender.tag)
        buildOnAirSubmenu()
    }

    @objc private func cancelOnAirSnooze() {
        snoozeManager?.cancelSnooze()
        buildOnAirSubmenu()
    }

    @objc private func toggleShowStats(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.showStats = isEnabled

        guard let menu = menu else { return }

        guard let aboutIndex = menu.items.firstIndex(where: { $0.title == "About MicGuard" }) else { return }

        if isEnabled {
            var insertIndex = aboutIndex

            let statsHeader = MenuItemFactory.createSectionHeader(title: "MicGuard Stats")
            statsHeader.tag = 499
            menu.insertItem(statsHeader, at: insertIndex)
            insertIndex += 1

            statsMenuItems.removeAll()
            for stat in StatType.allCases {
                let count = statsManager.get(stat: stat)
                let statItem = NSMenuItem(
                    title: "\(count) \(stat.displayName)",
                    action: nil,
                    keyEquivalent: ""
                )
                statItem.tag = 500 + StatType.allCases.firstIndex(of: stat)!
                statsMenuItems.append(statItem)
                menu.insertItem(statItem, at: insertIndex)
                insertIndex += 1
            }

            let resetStatsItem = NSMenuItem(
                title: "Reset Stats...",
                action: #selector(resetStats),
                keyEquivalent: ""
            )
            resetStatsItem.target = self
            resetStatsItem.tag = 510
            menu.insertItem(resetStatsItem, at: insertIndex)
            insertIndex += 1

            let statsSeparator = NSMenuItem.separator()
            statsSeparator.tag = 511
            menu.insertItem(statsSeparator, at: insertIndex)
        } else {
            let itemsToRemove = menu.items.filter { $0.tag >= 499 && $0.tag <= 511 }
            for item in itemsToRemove {
                menu.removeItem(item)
            }
            statsMenuItems.removeAll()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            self.statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
        }
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let deviceUID = sender.representedObject as? String else { return }
        deviceSubmenuBuilder?.selectDevice(uid: deviceUID)
        updateInputDeviceSubmenu()
    }

    @objc private func moveDeviceUp(_ sender: NSButton) {
        deviceSubmenuBuilder?.moveDeviceUp(index: sender.tag)
        updateInputDeviceSubmenu()
    }

    @objc private func moveDeviceDown(_ sender: NSButton) {
        deviceSubmenuBuilder?.moveDeviceDown(index: sender.tag)
        updateInputDeviceSubmenu()
    }

    @objc private func moveDeviceToTop(_ sender: NSButton) {
        deviceSubmenuBuilder?.moveDeviceToTop(index: sender.tag)
        updateInputDeviceSubmenu()
    }

    @objc private func useInputDevice(_ sender: NSButton) {
        deviceSubmenuBuilder?.useDevice(index: sender.tag)
        updateInputDeviceSubmenu()
        updateInputDeviceMenuItemTitle()
    }

    @objc private func removeDevice(_ sender: NSButton) {
        deviceSubmenuBuilder?.removeDevice(index: sender.tag)
        updateInputDeviceSubmenu()
    }

    @objc private func toggleOutputDeviceLock(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.outputDeviceLockEnabled = isEnabled

        NotificationCenter.default.post(name: .outputDeviceLockChanged, object: nil)
    }

    @objc private func toggleOutputAutoSwitch(_ sender: NSMenuItem) {
        let isEnabled = sender.state == .off
        sender.state = isEnabled ? .on : .off

        preferencesManager.outputAutoSwitchEnabled = isEnabled
    }

    @objc private func moveOutputDeviceUp(_ sender: NSButton) {
        outputDeviceSubmenuBuilder?.moveDeviceUp(index: sender.tag)
        updateOutputDeviceSubmenu()
    }

    @objc private func moveOutputDeviceDown(_ sender: NSButton) {
        outputDeviceSubmenuBuilder?.moveDeviceDown(index: sender.tag)
        updateOutputDeviceSubmenu()
    }

    @objc private func moveOutputDeviceToTop(_ sender: NSButton) {
        outputDeviceSubmenuBuilder?.moveDeviceToTop(index: sender.tag)
        updateOutputDeviceSubmenu()
    }

    @objc private func useOutputDevice(_ sender: NSButton) {
        outputDeviceSubmenuBuilder?.useDevice(index: sender.tag)
        updateOutputDeviceSubmenu()
        updateOutputDeviceMenuItemTitle()
    }

    @objc private func removeOutputDevice(_ sender: NSButton) {
        outputDeviceSubmenuBuilder?.removeDevice(index: sender.tag)
        updateOutputDeviceSubmenu()
    }

    @objc private func targetVolumeChanged(_ sender: NSSlider) {
        let value = sender.floatValue

        if let containerView = volumeSliderItem?.view,
           let label = containerView.viewWithTag(sender.tag + 1000) as? NSTextField {
            label.stringValue = "\(Int(value * 100))%"
        }

        let isMouseUp = NSApp.currentEvent?.type == .leftMouseUp
        if isMouseUp {
            preferencesManager.targetVolume = value
        }
    }

    @objc private func resetStats() {
        statsManager.reset()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MicGuard"
        alert.informativeText = """
        Version 1.0

        Your Mic, Your Rules.

        Prevents macOS and apps from hijacking your microphone selection or volume levels.

        No microphone access, no recordings, no data collection.

        © 2025
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let inputDeviceLockChanged = Notification.Name("inputDeviceLockChanged")
    static let inputVolumeLockChanged = Notification.Name("inputVolumeLockChanged")
    static let autoResetChanged = Notification.Name("autoResetChanged")
    static let preferredInputDeviceChanged = Notification.Name("preferredInputDeviceChanged")
    static let lockedVolumeChanged = Notification.Name("lockedVolumeChanged")
    static let outputDeviceLockChanged = Notification.Name("outputDeviceLockChanged")
    static let preferredOutputDeviceChanged = Notification.Name("preferredOutputDeviceChanged")
}
