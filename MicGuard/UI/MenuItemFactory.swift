//
//  MenuItemFactory.swift
//  MicGuard
//
//  Static factory methods for creating common NSMenuItem views
//

import Cocoa

enum MenuItemFactory {

    static func createSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem()

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 20))

        let label = NSTextField(frame: NSRect(x: 0, y: 2, width: 250, height: 16))
        label.stringValue = title
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor
        label.alignment = .center

        containerView.addSubview(label)
        item.view = containerView
        item.isEnabled = false
        return item
    }

    static func createVolumeSliderItem(value: Float, target: AnyObject, action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem()

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 30))

        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 5, width: 90, height: 20))
        titleLabel.stringValue = "Target Level:"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        let slider = NSSlider(frame: NSRect(x: 115, y: 5, width: 120, height: 20))
        slider.minValue = 0
        slider.maxValue = 1
        slider.floatValue = value
        slider.target = target
        slider.action = action
        slider.tag = tag
        slider.isContinuous = true

        let percentLabel = NSTextField(frame: NSRect(x: 240, y: 5, width: 40, height: 20))
        percentLabel.stringValue = "\(Int(value * 100))%"
        percentLabel.isEditable = false
        percentLabel.isBordered = false
        percentLabel.backgroundColor = .clear
        percentLabel.font = NSFont.systemFont(ofSize: 13)
        percentLabel.alignment = .left
        percentLabel.tag = tag + 1000

        containerView.addSubview(titleLabel)
        containerView.addSubview(slider)
        containerView.addSubview(percentLabel)

        item.view = containerView
        return item
    }

    static func radioButtonTitle(_ title: String, selected: Bool) -> String {
        let indicator = selected ? "◉" : "○"
        return "\(title)  \(indicator)"
    }
}
