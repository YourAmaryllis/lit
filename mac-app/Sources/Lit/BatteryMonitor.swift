import Foundation
import IOKit
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var percentage: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var timeToEmptyMinutes: Int?
    @Published var timeToFullMinutes: Int?
    @Published var cycleCount: Int?
    @Published var designCapacity: Int?
    @Published var maxCapacity: Int?
    @Published var temperatureCelsius: Double?

    /// Invoked after every refresh with the latest percentage, plugged-in, and charging state.
    var onUpdate: ((_ percentage: Int, _ isPluggedIn: Bool, _ isCharging: Bool) -> Void)?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var healthPercentage: Int? {
        guard let design = designCapacity, design > 0, let max = maxCapacity else { return nil }
        return Int((Double(max) / Double(design)) * 100.0)
    }

    func refresh() {
        refreshPowerSource()
        refreshSmartBatteryProperties()
        onUpdate?(percentage, isPluggedIn, isCharging)
    }

    private func refreshPowerSource() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else { return }

        percentage = description[kIOPSCurrentCapacityKey] as? Int ?? percentage
        isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        timeToEmptyMinutes = description[kIOPSTimeToEmptyKey] as? Int
        timeToFullMinutes = description[kIOPSTimeToFullChargeKey] as? Int
    }

    private func refreshSmartBatteryProperties() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func intProperty(_ key: String) -> Int? {
            guard let cfValue = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
                return nil
            }
            return (cfValue.takeRetainedValue() as? NSNumber)?.intValue
        }

        cycleCount = intProperty("CycleCount")
        designCapacity = intProperty("DesignCapacity")
        // On Apple Silicon, top-level "MaxCapacity" is already a 0-100 percentage,
        // not a mAh value comparable to DesignCapacity — "AppleRawMaxCapacity" is
        // the real mAh figure. Older Intel Macs only expose "MaxCapacity" in mAh.
        maxCapacity = intProperty("AppleRawMaxCapacity") ?? intProperty("MaxCapacity")
        if let tempRaw = intProperty("Temperature") {
            temperatureCelsius = Double(tempRaw) / 100.0
        }
    }
}
