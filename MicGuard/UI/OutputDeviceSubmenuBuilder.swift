//
//  OutputDeviceSubmenuBuilder.swift
//  MicGuard
//
//  Builds and manages the output device priority submenu
//

import Cocoa

class OutputDeviceSubmenuBuilder {

    // MARK: - Properties

    private let audioDeviceManager: AudioDeviceManaging
    private let preferencesManager: PreferencesManaging
    private weak var outputDeviceSubmenu: NSMenu?

    // MARK: - Initialization

    init(audioDeviceManager: AudioDeviceManaging,
         preferencesManager: PreferencesManaging,
         submenu: NSMenu?) {
        self.audioDeviceManager = audioDeviceManager
        self.preferencesManager = preferencesManager
        self.outputDeviceSubmenu = submenu
    }

    // MARK: - Public Methods

    func updateSubmenu(target: AnyObject,
                       moveUpAction: Selector,
                       moveDownAction: Selector,
                       removeAction: Selector,
                       useAction: Selector) {
        outputDeviceSubmenu?.removeAllItems()

        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        let currentDeviceUID = audioDeviceManager.defaultOutputDevice?.uid
        let allDevices = audioDeviceManager.outputDevices

        // Get devices from priority list (in order), with name-based fallback
        var orderedDevices: [(device: AudioDevice?, uid: String, priority: Int)] = []
        for (index, uid) in priorityOrder.enumerated() {
            var device = allDevices.first { $0.uid == uid }
            if device == nil, let cachedName = preferencesManager.cachedDeviceName(for: uid) {
                let nameMatches = allDevices.filter { $0.name == cachedName }
                if nameMatches.count == 1 {
                    device = nameMatches[0]
                    preferencesManager.replaceOutputDeviceUID(oldUID: uid, newUID: nameMatches[0].uid)
                }
            }
            orderedDevices.append((device: device, uid: device?.uid ?? uid, priority: index))
        }

        // Add any devices not in priority list at the end
        let updatedPriorityOrder = preferencesManager.preferredOutputDeviceOrder
        for device in allDevices {
            let knownByUID = updatedPriorityOrder.contains(device.uid)
            let knownByName = updatedPriorityOrder.contains { uid in
                preferencesManager.cachedDeviceName(for: uid) == device.name
            }
            if !knownByUID && !knownByName {
                preferencesManager.addOutputDeviceToOrder(device.uid)
                orderedDevices.append((device: device, uid: device.uid, priority: updatedPriorityOrder.count))
            }
        }

        // Cache names for all connected devices
        for entry in orderedDevices {
            if let device = entry.device {
                preferencesManager.cacheDeviceName(uid: device.uid, name: device.name)
            }
        }

        if orderedDevices.isEmpty {
            let emptyItem = NSMenuItem(title: "No output devices found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            outputDeviceSubmenu?.addItem(emptyItem)
            return
        }

        // Create menu items for each device
        for (index, entry) in orderedDevices.enumerated() {
            let isConnected = entry.device != nil
            let isActive = entry.uid == currentDeviceUID

            let baseName: String
            if let device = entry.device {
                baseName = device.name
            } else {
                baseName = preferencesManager.cachedDeviceName(for: entry.uid) ?? entry.uid
            }
            let displayName = isConnected ? baseName : "\(baseName) (disconnected)"

            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 22))

            // Checkmark for active device
            let prefix = isActive ? "✓ " : "   "
            let label = NSTextField(labelWithString: "\(prefix)#\(index + 1)  \(displayName)")
            label.font = NSFont.menuFont(ofSize: 13)
            if isActive {
                label.textColor = .systemBlue
            } else {
                label.textColor = isConnected ? .labelColor : .tertiaryLabelColor
            }
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 8, y: 3, width: 200, height: 16)
            containerView.addSubview(label)

            let buttonY: CGFloat = 1
            let buttonSize: CGFloat = 20

            // "Use" button only for connected, non-active devices
            if isConnected && !isActive {
                let useButton = NSButton(frame: NSRect(x: 215, y: buttonY, width: 32, height: buttonSize))
                useButton.title = "Use"
                useButton.bezelStyle = .roundRect
                useButton.font = NSFont.systemFont(ofSize: 10)
                useButton.target = target
                useButton.action = useAction
                useButton.tag = index
                containerView.addSubview(useButton)
            }

            // Priority arrows for all devices (connected and disconnected)
            let upButton = NSButton(frame: NSRect(x: 255, y: buttonY, width: buttonSize, height: buttonSize))
            upButton.title = "↑"
            upButton.bezelStyle = .roundRect
            upButton.font = NSFont.systemFont(ofSize: 12)
            upButton.target = target
            upButton.action = moveUpAction
            upButton.tag = index
            upButton.isEnabled = index > 0
            containerView.addSubview(upButton)

            let downButton = NSButton(frame: NSRect(x: 280, y: buttonY, width: buttonSize, height: buttonSize))
            downButton.title = "↓"
            downButton.bezelStyle = .roundRect
            downButton.font = NSFont.systemFont(ofSize: 12)
            downButton.target = target
            downButton.action = moveDownAction
            downButton.tag = index
            downButton.isEnabled = index < orderedDevices.count - 1
            containerView.addSubview(downButton)

            // Remove button only for disconnected devices
            if !isConnected {
                let removeButton = NSButton(frame: NSRect(x: 305, y: buttonY, width: buttonSize, height: buttonSize))
                removeButton.title = "✕"
                removeButton.bezelStyle = .roundRect
                removeButton.font = NSFont.systemFont(ofSize: 11)
                removeButton.target = target
                removeButton.action = removeAction
                removeButton.tag = index
                removeButton.contentTintColor = .secondaryLabelColor
                containerView.addSubview(removeButton)
            }

            let menuItem = NSMenuItem()
            menuItem.view = containerView
            menuItem.representedObject = entry.uid
            menuItem.state = isActive ? .on : .off
            outputDeviceSubmenu?.addItem(menuItem)
        }

        outputDeviceSubmenu?.addItem(NSMenuItem.separator())

        let footerItem = NSMenuItem()
        let footerView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 30))

        let footerLabel = NSTextField(frame: NSRect(x: 20, y: 5, width: 330, height: 20))
        footerLabel.stringValue = "ℹ️ Devices auto-select by priority order"
        footerLabel.isEditable = false
        footerLabel.isBordered = false
        footerLabel.backgroundColor = .clear
        footerLabel.font = NSFont.systemFont(ofSize: 10)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.alignment = .left

        footerView.addSubview(footerLabel)
        footerItem.view = footerView
        footerItem.isEnabled = false
        outputDeviceSubmenu?.addItem(footerItem)
    }

    // MARK: - Device Reorder Actions

    func moveDeviceUp(index: Int) {
        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard index > 0, index < priorityOrder.count else { return }

        let uid = priorityOrder[index]
        preferencesManager.moveOutputDevice(uid: uid, direction: .up)
        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }

    func moveDeviceDown(index: Int) {
        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard index < priorityOrder.count - 1 else { return }

        let uid = priorityOrder[index]
        preferencesManager.moveOutputDevice(uid: uid, direction: .down)
        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }

    func moveDeviceToTop(index: Int) {
        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard index > 0, index < priorityOrder.count else { return }

        let uid = priorityOrder[index]
        preferencesManager.moveOutputDevice(uid: uid, direction: .toTop)
        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }

    func useDevice(index: Int) {
        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard index >= 0, index < priorityOrder.count else { return }

        let uid = priorityOrder[index]
        guard let device = audioDeviceManager.device(forUID: uid) else { return }

        audioDeviceManager.setDefaultOutputDevice(device)

        preferencesManager.preferredOutputDeviceUID = uid

        // Move to top of priority list
        if index > 0 {
            preferencesManager.moveOutputDevice(uid: uid, direction: .toTop)
        }

        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }

    func removeDevice(index: Int) {
        let priorityOrder = preferencesManager.preferredOutputDeviceOrder
        guard index >= 0, index < priorityOrder.count else { return }

        let uid = priorityOrder[index]
        preferencesManager.removeOutputDeviceFromOrder(uid)

        if preferencesManager.preferredOutputDeviceUID == uid {
            preferencesManager.preferredOutputDeviceUID = nil
        }

        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }

    func selectDevice(uid: String) {
        preferencesManager.preferredOutputDeviceUID = uid

        if !preferencesManager.preferredOutputDeviceOrder.contains(uid) {
            preferencesManager.addOutputDeviceToOrder(uid)
        }

        NotificationCenter.default.post(name: .preferredOutputDeviceChanged, object: uid)
    }
}
