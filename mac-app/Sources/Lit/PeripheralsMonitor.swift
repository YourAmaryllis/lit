import Foundation
import IOKit

struct PeripheralDevice: Identifiable {
    let id: String
    let name: String
    let batteryPercent: Int
}

/// Reads battery levels for Bluetooth accessories (AirPods, Magic Mouse/Keyboard/
/// Trackpad, and anything else exposing the standard HID battery property) via
/// the same IOKit service macOS itself uses to drive the Bluetooth menu's battery
/// icons — no IOBluetooth pairing/authorization dance required.
@MainActor
final class PeripheralsMonitor: ObservableObject {
    @Published private(set) var devices: [PeripheralDevice] = []

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        devices = Self.scanHIDBatteryDevices()
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
