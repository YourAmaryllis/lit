import Foundation
import UserNotifications

@MainActor
final class AlertsManager: ObservableObject {
    @Published private(set) var thresholds: [Int]

    private var firedThresholds: Set<Int> = []
    private var hasAlertedHealthyBand = false
    private var lastPluggedIn: Bool?
    private let defaultsKey = "lit.alertThresholds"

    init() {
        if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [Int], !saved.isEmpty {
            thresholds = saved.sorted(by: >)
        } else {
            thresholds = [20, 10, 5]
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func addThreshold(_ value: Int) {
        guard value > 0, value < 100, !thresholds.contains(value) else { return }
        thresholds.append(value)
        thresholds.sort(by: >)
        persist()
    }

    func removeThreshold(_ value: Int) {
        thresholds.removeAll { $0 == value }
        persist()
    }

    /// Call whenever the battery reading updates. Covers two kinds of alerts:
    /// - Low-battery thresholds: fire once when percentage drops to/below a
    ///   configured level on battery power, re-arm once plugged in.
    /// - Lifecycle events: plugged in, unplugged, and crossing 80% while
    ///   charging (the healthy-band cutoff), each firing once per transition.
    func evaluate(percentage: Int, isPluggedIn: Bool, isCharging: Bool) {
        if let last = lastPluggedIn, last != isPluggedIn {
            if isPluggedIn {
                fireLifecycle(title: "Charger Connected", body: "Your Mac is now charging.")
            } else {
                fireLifecycle(title: "Unplugged", body: "Running on battery power.")
                hasAlertedHealthyBand = false
            }
        }
        lastPluggedIn = isPluggedIn

        if isPluggedIn {
            if isCharging && percentage >= 80 && !hasAlertedHealthyBand {
                fireLifecycle(title: "Battery at 80%", body: "Unplug now to keep your battery healthy long-term.")
                hasAlertedHealthyBand = true
            }
            firedThresholds.removeAll()
            return
        }

        for threshold in thresholds where percentage <= threshold && !firedThresholds.contains(threshold) {
            fire(threshold: threshold)
            firedThresholds.insert(threshold)
        }
    }

    private func fire(threshold: Int) {
        let title = "Battery at \(threshold)%"
        let body = threshold <= 10
            ? "Plug in soon — your Mac is about to run low."
            : "Battery is getting low."
        post(identifier: "lit.battery.\(threshold)", title: title, body: body)
    }

    private func fireLifecycle(title: String, body: String) {
        post(identifier: "lit.lifecycle.\(title)", title: title, body: body)
    }

    private func post(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(identifier).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func persist() {
        UserDefaults.standard.set(thresholds, forKey: defaultsKey)
    }
}
