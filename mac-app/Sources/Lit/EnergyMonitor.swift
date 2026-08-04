import Foundation
import AppKit
import Darwin

struct AppEnergyUsage: Identifiable {
    let id: String
    let name: String
    /// Share of total measured energy impact across all running apps, 0-100 —
    /// summing the top N shown will legitimately be less than 100 if there are
    /// more running apps than are displayed.
    let percent: Double
    let watts: Double
}

private struct EnergySample {
    let energyNanojoules: UInt64
    let timestamp: Date
}

/// Real per-app energy, not a CPU-time proxy — `proc_pid_rusage(pid,
/// RUSAGE_INFO_V6, ...)` exposes `ri_energy_nj`, a cumulative nanojoule
/// counter the kernel bills to each process (the same underlying number
/// Activity Monitor's Energy tab is built on). It's public API in <libproc.h>
/// (no dlopen/private framework), and needs no root for same-user processes.
/// The counter is cumulative since process launch, so usage here is a power
/// reading (watts) computed from the delta between two samples.
@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var topApps: [AppEnergyUsage] = []

    private var timer: Timer?
    private var previousSamples: [pid_t: EnergySample] = [:]

    init() {
        refresh()
        // .common mode keeps this firing even while the run loop is in
        // event-tracking mode (e.g. the dropdown open) — see BatteryMonitor.
        let refreshTimer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func refresh() {
        let apps = NSWorkspace.shared.runningApplications
        let now = Date()

        var currentSamples: [pid_t: EnergySample] = [:]
        var wattsByPid: [pid_t: Double] = [:]

        for app in apps {
            let pid = app.processIdentifier
            guard let energy = Self.energyNanojoules(forPid: pid) else { continue }
            currentSamples[pid] = EnergySample(energyNanojoules: energy, timestamp: now)

            if let previous = previousSamples[pid], energy >= previous.energyNanojoules {
                let deltaEnergyJoules = Double(energy - previous.energyNanojoules) / 1_000_000_000
                let deltaSeconds = now.timeIntervalSince(previous.timestamp)
                if deltaSeconds > 0 {
                    wattsByPid[pid] = deltaEnergyJoules / deltaSeconds
                }
            }
        }

        previousSamples = currentSamples

        let totalWatts = wattsByPid.values.reduce(0, +)
        guard totalWatts > 0 else {
            topApps = []
            return
        }

        var results: [AppEnergyUsage] = []
        for app in apps {
            guard let watts = wattsByPid[app.processIdentifier], let name = app.localizedName else { continue }
            results.append(AppEnergyUsage(
                id: String(app.processIdentifier),
                name: name,
                percent: (watts / totalWatts) * 100,
                watts: watts
            ))
        }

        topApps = results.sorted { $0.percent > $1.percent }
    }

    private static func energyNanojoules(forPid pid: pid_t) -> UInt64? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V6, rawPointer)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_energy_nj
    }
}
