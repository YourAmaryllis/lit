import Foundation
import IOKit
import UserNotifications

struct PeripheralDevice: Identifiable {
    let id: String
    let name: String
    let batteryPercent: Int
}

/// Reads battery levels for Bluetooth accessories (AirPods, Beats, Magic Mouse/
/// Keyboard/Trackpad, and anything else exposing the standard HID battery
/// property) via the same IOKit service macOS itself uses to drive the
/// Bluetooth menu's battery icons — no IOBluetooth pairing/authorization dance
/// required. Also fires low-battery / fully-charged alerts per device.
@MainActor
final class PeripheralsMonitor: ObservableObject {
    @Published private(set) var devices: [PeripheralDevice] = []

    private var lowBatteryFired: Set<String> = []
    private var fullyChargedFired: Set<String> = []
    private var timer: Timer?

    init() {
        refresh()
        // .common mode keeps this firing even while the run loop is in
        // event-tracking mode (e.g. the dropdown open) — see BatteryMonitor.
        let refreshTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func refresh() {
        let updated = Self.scanHIDBatteryDevices()
        for device in updated {
            evaluateAlerts(for: device)
        }
        devices = updated
    }

    private func evaluateAlerts(for device: PeripheralDevice) {
        if device.batteryPercent <= 20 {
            if !lowBatteryFired.contains(device.id) {
                notify(
                    identifier: "lit.device.low.\(device.id)",
                    title: "\(device.name) Low Battery",
                    body: "\(device.batteryPercent)% remaining."
                )
                lowBatteryFired.insert(device.id)
            }
        } else if device.batteryPercent > 30 {
            lowBatteryFired.remove(device.id)
        }

        if device.batteryPercent >= 100 {
            if !fullyChargedFired.contains(device.id) {
                notify(
                    identifier: "lit.device.full.\(device.id)",
                    title: "\(device.name) Fully Charged",
                    body: "Ready to go."
                )
                fullyChargedFired.insert(device.id)
            }
        } else {
            fullyChargedFired.remove(device.id)
        }
    }

    private func notify(identifier: String, title: String, body: String) {
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

    private static func scanHIDBatteryDevices() -> [PeripheralDevice] {
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [PeripheralDevice] = []

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }

            guard let batteryPercent = (property("BatteryPercent") as? NSNumber)?.intValue else { continue }
            if (property("Built-In") as? Bool) == true { continue }

            let name = (property("Product") as? String) ?? "Bluetooth Device"
            let identifier = (property("SerialNumber") as? String) ?? name

            results.append(PeripheralDevice(id: identifier, name: name, batteryPercent: batteryPercent))
        }

        return results
    }
}
