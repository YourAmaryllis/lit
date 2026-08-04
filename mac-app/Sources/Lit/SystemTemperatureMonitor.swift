import Foundation

enum ThermalPressure: String {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

/// CPU/GPU temperature via SMC (see SMCReader.swift for why this needs a
/// private, undocumented mechanism), plus the public `ProcessInfo.thermalState`
/// as a zero-risk qualitative complement that works on any Mac regardless of
/// whether the SMC keys below are recognized.
///
/// The SMC key list is specific to Apple Silicon M4 (verified against this
/// exact machine — MacBook Air, Mac16,12, base M4 — via real hardware
/// during development; see mac-app/DATA_SOURCES.md). Other chip generations
/// (M1/M2/M3, Pro/Max/Ultra variants, Intel) will simply get no CPU/GPU
/// temperature — SMCReader returns nil for keys that don't exist on that
/// hardware, never crashes or shows wrong data for it.
@MainActor
final class SystemTemperatureMonitor: ObservableObject {
    @Published private(set) var cpuTemperatureCelsius: Double?
    @Published private(set) var gpuTemperatureCelsius: Double?
    @Published private(set) var thermalPressure: ThermalPressure

    private let smc = SMCReader()
    private var timer: Timer?

    // M4 (base) efficiency + performance core dies, and GPU dies —
    // github.com/exelban/stats Modules/Sensors/values.swift, sourced from
    // acidanthera/VirtualSMC's SMCSensorKeys.txt. [String] is Sendable, but
    // a static property on an @MainActor class is still actor-isolated
    // unless marked nonisolated — needed since averageTemperature runs
    // inside Task.detached.
    private nonisolated static let cpuKeys = [
        "Te05", "Te0S", "Te09", "Te0H", // efficiency cores 1-4
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e", // performance cores 1-8
    ]
    private nonisolated static let gpuKeys = ["Tg0G", "Tg0H"]

    init() {
        thermalPressure = ThermalPressure(ProcessInfo.processInfo.thermalState)
        refresh()

        let refreshTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func refresh() {
        thermalPressure = ThermalPressure(ProcessInfo.processInfo.thermalState)

        Task.detached(priority: .utility) { [smc] in
            let cpu = Self.averageTemperature(keys: Self.cpuKeys, smc: smc)
            let gpu = Self.averageTemperature(keys: Self.gpuKeys, smc: smc)
            await MainActor.run { [weak self] in
                self?.cpuTemperatureCelsius = cpu
                self?.gpuTemperatureCelsius = gpu
            }
        }
    }

    private nonisolated static func averageTemperature(keys: [String], smc: SMCReader) -> Double? {
        let readings = keys.compactMap { smc.readTemperature(key: $0) }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }
}
