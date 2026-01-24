//
//  NotificationManager.swift
//  MicGuard
//
//  Handles user notifications (currently unused — will be wired up later)
//

import Foundation
import UserNotifications

protocol NotificationManaging {
    func requestAuthorization()
    func showNotification(title: String, body: String)
}

class NotificationManager: NotificationManaging {

    static let shared = NotificationManager()

    private var isAuthorized = false

    private lazy var notificationCenter: UNUserNotificationCenter = {
        return UNUserNotificationCenter.current()
    }()

    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.isAuthorized = granted
        }
    }

    func showNotification(title: String, body: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }
}

class MockNotificationManager: NotificationManaging {
    var authorizationRequested = false
    var notifications: [(title: String, body: String)] = []

    func requestAuthorization() {
        authorizationRequested = true
    }

    func showNotification(title: String, body: String) {
        notifications.append((title: title, body: body))
    }
}
