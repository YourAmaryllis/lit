import Foundation
import UserNotifications

@MainActor
final class AlertsManager: ObservableObject {
    @Published private(set) var thresholds: [Int]

    private var firedThresholds: Set<Int> = []
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

    /// Call whenever the battery reading updates. Fires a notification the first
    /// time the percentage drops to or below a configured threshold while on
    /// battery power, then re-arms that threshold once the Mac is plugged in.
    func evaluate(percentage: Int, isPluggedIn: Bool) {
        if isPluggedIn {
            firedThresholds.removeAll()
            return
        }

        for threshold in thresholds where percentage <= threshold && !firedThresholds.contains(threshold) {
            fire(threshold: threshold)
            firedThresholds.insert(threshold)
        }
    }

    private func fire(threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Battery at \(threshold)%"
        content.body = threshold <= 10
            ? "Plug in soon — your Mac is about to run low."
            : "Battery is getting low."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lit.battery.\(threshold).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func persist() {
        UserDefaults.standard.set(thresholds, forKey: defaultsKey)
    }
}
