import Foundation
import IOKit
import IOKit.ps

enum HealthCondition: String {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var percentage: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isFullyCharged: Bool = false
    @Published var timeToEmptyMinutes: Int?
    @Published var timeToFullMinutes: Int?

    // Health snapshot — refreshed every 2 minutes, like Juicy does, since these
    // values barely move minute to minute and don't need live polling.
    @Published var cycleCount: Int?
    @Published var designCapacityMah: Int?
    @Published var fullCapacityMah: Int?
    @Published var remainingCapacityMah: Int?
    @Published var temperatureCelsius: Double?
    @Published var lastHealthUpdate: Date?

    // Electrical — refreshed on every fast tick.
    @Published var voltageVolts: Double?
    @Published var amperageMilliamps: Int?
    @Published var adapterWattage: Int?

    /// Invoked after every fast refresh with the latest percentage, plugged-in, and charging state.
    var onUpdate: ((_ percentage: Int, _ isPluggedIn: Bool, _ isCharging: Bool) -> Void)?

    private var timer: Timer?
    private var lastHealthRefresh: Date = .distantPast
    private let healthRefreshInterval: TimeInterval = 120

    init() {
        refresh()
        // Timer.scheduledTimer only fires in the default run loop mode, which
        // pauses while the run loop is in event-tracking mode — e.g. while the
        // menu bar dropdown is open, or during any mouse-tracking interaction.
        // Adding it in .common mode keeps it firing regardless.
        let refreshTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    var healthPercentage: Int? {
        guard let design = designCapacityMah, design > 0, let full = fullCapacityMah else { return nil }
        return Int((Double(full) / Double(design)) * 100.0)
    }

    var healthCondition: HealthCondition? {
        guard let health = healthPercentage else { return nil }
        switch health {
        case 80...: return .good
        case 50..<80: return .fair
        default: return .poor
        }
    }

    var temperatureFahrenheit: Double? {
        temperatureCelsius.map { $0 * 9.0 / 5.0 + 32.0 }
    }

    /// Apple's documented safe operating range for these devices is 0-35°C.
    var isTemperatureNormal: Bool? {
        temperatureCelsius.map { $0 >= 0 && $0 <= 35 }
    }

    /// Instantaneous power flowing into (+) or out of (-) the battery, in watts.
    var batteryWattage: Double? {
        guard let voltage = voltageVolts, let amperage = amperageMilliamps else { return nil }
        return voltage * (Double(amperage) / 1000.0)
    }

    /// Estimated system power draw while actively charging: the adapter's rated
    /// wattage minus what's measurably going into the battery. This is only a
    /// real number when the Mac is drawing the adapter's full rated capacity —
    /// true for small/low-wattage adapters running at their limit, false for a
    /// high-wattage adapter under light load (it would overstate system draw by
    /// the unused headroom). There's no public API for true live input power,
    /// so this is the best available estimate, not an independent measurement.
    var estimatedSystemWattageWhileCharging: Double? {
        guard isCharging, let adapterW = adapterWattage, let batteryW = batteryWattage, batteryW > 0 else {
            return nil
        }
        return max(0, Double(adapterW) - batteryW)
    }

    func refresh() {
        refreshPowerSource()
        refreshElectrical()
        if Date().timeIntervalSince(lastHealthRefresh) >= healthRefreshInterval {
            refreshHealthSnapshot()
        }
        onUpdate?(percentage, isPluggedIn, isCharging)
    }

    /// Bypasses the 2-minute throttle for an explicit "refresh now" request.
    func refreshHealthNow() {
        refreshHealthSnapshot()
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

    private func refreshElectrical() {
        withSmartBatteryService { property in
            self.voltageVolts = (property("Voltage") as? NSNumber).map { Double(truncating: $0) / 1000.0 }
            self.amperageMilliamps = (property("InstantAmperage") as? NSNumber)?.intValue
                ?? (property("Amperage") as? NSNumber)?.intValue
            self.isFullyCharged = (property("FullyCharged") as? Bool) ?? self.isFullyCharged
            if let adapter = property("AdapterDetails") as? [String: Any] {
                self.adapterWattage = (adapter["Watts"] as? NSNumber)?.intValue
            } else {
                self.adapterWattage = nil
            }
        }
    }

    private func refreshHealthSnapshot() {
        withSmartBatteryService { property in
            self.cycleCount = (property("CycleCount") as? NSNumber)?.intValue
            self.designCapacityMah = (property("DesignCapacity") as? NSNumber)?.intValue
            // On Apple Silicon, top-level "MaxCapacity" is already a 0-100 percentage,
            // not a mAh value comparable to DesignCapacity — "AppleRawMaxCapacity" is
            // the real mAh figure. Older Intel Macs only expose "MaxCapacity" in mAh.
            self.fullCapacityMah = (property("AppleRawMaxCapacity") as? NSNumber)?.intValue
                ?? (property("MaxCapacity") as? NSNumber)?.intValue
            self.remainingCapacityMah = (property("AppleRawCurrentCapacity") as? NSNumber)?.intValue
            if let tempRaw = (property("Temperature") as? NSNumber)?.doubleValue {
                self.temperatureCelsius = tempRaw / 100.0
            }
        }
        lastHealthRefresh = Date()
        lastHealthUpdate = lastHealthRefresh
    }

    private func withSmartBatteryService(_ body: (_ property: (String) -> Any?) -> Void) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        body { key in
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
    }
}
