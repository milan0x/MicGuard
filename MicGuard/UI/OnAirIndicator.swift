//
//  OnAirIndicator.swift
//  MicGuard
//
//  Manages the ON AIR status bar indicator and flash animation
//

import Cocoa

class OnAirIndicator {

    // MARK: - Properties

    private weak var statusItem: NSStatusItem?
    private let preferencesManager: PreferencesManaging

    private(set) var isMicActive: Bool = false

    // Flash animation state
    private var isFlashing: Bool = false
    private var flashTimer: Timer?
    private var flashCount: Int = 0
    private let maxFlashes: Int = 3
    private let flashDuration: TimeInterval = 0.5

    // MARK: - Initialization

    init(statusItem: NSStatusItem?, preferencesManager: PreferencesManaging) {
        self.statusItem = statusItem
        self.preferencesManager = preferencesManager
    }

    // MARK: - Public Methods

    func update(isInUse: Bool, force: Bool = false) {
        if !force {
            guard isInUse != isMicActive else { return }
        }
        isMicActive = isInUse

        guard let button = statusItem?.button else { return }

        if preferencesManager.showOnAirIndicator && !preferencesManager.isOnAirSnoozed && isMicActive {
            button.attributedTitle = Self.onAirAttributedString()
            button.image = nil
        } else {
            button.attributedTitle = NSAttributedString()
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "MicGuard")
            button.image?.isTemplate = true
        }
    }

    func flash() {
        guard !isFlashing else { return }

        isFlashing = true
        flashCount = 0

        flashTimer?.invalidate()
        let timer = Timer(timeInterval: flashDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            guard self.statusItem?.button != nil else {
                timer.invalidate()
                self.isFlashing = false
                return
            }

            let alpha: CGFloat = (self.flashCount % 2 == 0) ? 0.0 : 1.0
            self.statusItem?.button?.attributedTitle = Self.onAirAttributedString(alpha: alpha)
            self.statusItem?.button?.image = nil

            self.flashCount += 1

            if self.flashCount >= self.maxFlashes * 2 {
                timer.invalidate()
                self.isFlashing = false
                self.flashCount = 0

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    // Re-evaluate current state instead of using stale captured value
                    self.update(isInUse: self.isMicActive, force: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flashTimer = timer
    }

    // MARK: - Private

    private static func onAirAttributedString(alpha: CGFloat = 1.0) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.minimumLineHeight = 20
        paragraphStyle.maximumLineHeight = 20

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .backgroundColor: NSColor.red.withAlphaComponent(alpha),
            .paragraphStyle: paragraphStyle,
            .baselineOffset: -1
        ]

        return NSAttributedString(string: " ON AIR ", attributes: attributes)
    }
}
