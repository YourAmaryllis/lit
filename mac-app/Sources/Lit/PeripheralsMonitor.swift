import Foundation
import IOKit
import UserNotifications

struct PeripheralDevice: Identifiable {
    let id: String
    let name: String
    let batteryPercent: Int
}

/// Reads battery levels for two kinds of connected devices, merged into one
/// list, with shared low-battery/fully-charged alert logic:
///
/// 1. Bluetooth HID accessories (AirPods, Beats, Magic Mouse/Keyboard/
///    Trackpad) via `AppleDeviceManagementHIDEventService` — the same IOKit
///    service macOS itself uses to drive the Bluetooth menu's battery icons.
///
/// 2. iPhone/iPad via `libimobiledevice` (LGPL-2.1, invoked as an external
///    subprocess — not linked into this binary, so this stays MIT-clean).
///    There is no reliable Bluetooth-only API for this: researched first
///    (see mac-app/DATA_SOURCES.md) and confirmed the real mechanism other
///    tools use is USB-once-then-Wi-Fi-sync via the private lockdownd
///    protocol, not proximity Bluetooth. Requires `idevice_id`/`ideviceinfo`
///    to be installed (`brew install libimobiledevice`) and the device to
///    have been USB-trusted at least once; gracefully shows nothing if the
///    tool isn't installed or no device is reachable — never crashes or
///    errors visibly for that case.
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
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let hidDevices = Self.scanHIDBatteryDevices()
            let idevices = Self.scanIDevices()
            let combined = hidDevices + idevices
            await MainActor.run { [weak self] in
                guard let self else { return }
                for device in combined {
                    self.evaluateAlerts(for: device)
                }
                self.devices = combined
            }
        }
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

    private nonisolated static func scanHIDBatteryDevices() -> [PeripheralDevice] {
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

    // MARK: - iPhone/iPad via libimobiledevice

    private nonisolated static func scanIDevices() -> [PeripheralDevice] {
        guard let ideviceIDPath = findBinary("idevice_id"),
              let ideviceInfoPath = findBinary("ideviceinfo")
        else {
            return []
        }

        let usbUDIDs = Set(runLines(ideviceIDPath, ["-l"]))
        let networkUDIDs = Set(runLines(ideviceIDPath, ["-n"]))

        var results: [PeripheralDevice] = []
        for udid in usbUDIDs.union(networkUDIDs) {
            // Prefer the USB session if a device is reachable both ways —
            // no reason to route through Wi-Fi sync when the cable's right there.
            let isNetworkOnly = !usbUDIDs.contains(udid)
            var args = ["-u", udid]
            if isNetworkOnly { args.append("-n") }

            let battery = runKeyValue(ideviceInfoPath, args + ["-q", "com.apple.mobile.battery"])
            guard let capacity = battery["BatteryCurrentCapacity"].flatMap(Int.init) else { continue }

            let name = runLines(ideviceInfoPath, args + ["-k", "DeviceName"]).first ?? "iPhone/iPad"
            results.append(PeripheralDevice(id: "idevice-\(udid)", name: name, batteryPercent: capacity))
        }

        return results
    }

    private nonisolated static func findBinary(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private nonisolated static func runLines(_ executablePath: String, _ arguments: [String]) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses ideviceinfo's default "Key: Value" text output (one pair per line).
    private nonisolated static func runKeyValue(_ executablePath: String, _ arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in runLines(executablePath, arguments) {
            guard let separator = line.range(of: ": ") else { continue }
            let key = String(line[line.startIndex..<separator.lowerBound])
            let value = String(line[separator.upperBound...])
            result[key] = value
        }
        return result
    }
}
