import Foundation
import IOKit
import UserNotifications

struct PeripheralDevice: Identifiable {
    let id: String
    let name: String
    let batteryPercent: Int
    /// nil when unknown (Bluetooth HID accessories don't expose this).
    let isCharging: Bool?
    /// SF Symbol override for device type (e.g. "ipad", "iphone"). nil falls
    /// back to the generic battery-level glyph used for Bluetooth accessories.
    let symbolOverride: String?

    init(id: String, name: String, batteryPercent: Int, isCharging: Bool? = nil, symbolOverride: String? = nil) {
        self.id = id
        self.name = name
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.symbolOverride = symbolOverride
    }
}

/// Reads battery levels for three kinds of connected devices, merged into one
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
///
/// 3. Android via `adb`/`dumpsys battery` (Apache 2.0, also an external
///    subprocess) — public, documented AOSP tooling, unlike the iOS path.
///    Requires Developer Options → USB debugging enabled on the phone and
///    one-time on-device authorization; gracefully shows nothing otherwise.
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
            let androidDevices = Self.scanAndroidDevices()
            let combined = hidDevices + idevices + androidDevices
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
            let isCharging = battery["BatteryIsCharging"].map { $0 == "true" }

            let name = runLines(ideviceInfoPath, args + ["-k", "DeviceName"]).first ?? "iPhone/iPad"
            let deviceClass = runLines(ideviceInfoPath, args + ["-k", "DeviceClass"]).first
            let symbol: String? = switch deviceClass {
            case "iPad": "ipad"
            case "iPhone": "iphone"
            default: nil
            }

            results.append(PeripheralDevice(
                id: "idevice-\(udid)",
                name: name,
                batteryPercent: capacity,
                isCharging: isCharging,
                symbolOverride: symbol
            ))
        }

        return results
    }

    // MARK: - Android via adb

    /// `adb`/`dumpsys` is public, documented AOSP tooling (Apache 2.0) —
    /// unlike the iOS path, this isn't a reverse-engineered private protocol.
    /// The real friction is on the phone's side: this only works if
    /// Developer Options → USB debugging is enabled (off by default, and
    /// most non-technical users have never turned it on) and the device has
    /// been authorized for this Mac at least once (a one-time on-device
    /// "Allow USB debugging?" prompt, same idea as iOS's USB trust).
    /// Gracefully contributes nothing if `adb` isn't installed, no device is
    /// attached, or a device is attached but not yet authorized.
    private nonisolated static func scanAndroidDevices() -> [PeripheralDevice] {
        guard let adbPath = findBinary("adb") else { return [] }

        let lines = runLines(adbPath, ["devices"])
        let serials = lines.compactMap { line -> String? in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[1] == "device" else { return nil }
            return String(parts[0])
        }

        var results: [PeripheralDevice] = []
        for serial in serials {
            let battery = runKeyValue(adbPath, ["-s", serial, "shell", "dumpsys", "battery"])
            guard let level = battery["level"].flatMap(Int.init) else { continue }

            // Android BatteryManager status constants: 2 = CHARGING, 5 = FULL.
            let statusCode = battery["status"].flatMap(Int.init)
            let isCharging = statusCode.map { $0 == 2 || $0 == 5 }

            let name = runLines(adbPath, ["-s", serial, "shell", "getprop", "ro.product.model"]).first
                ?? "Android Device"

            results.append(PeripheralDevice(
                id: "android-\(serial)",
                name: name,
                batteryPercent: level,
                isCharging: isCharging,
                symbolOverride: "candybarphone"
            ))
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
