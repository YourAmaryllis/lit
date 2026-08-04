import Foundation
import AppKit

struct AppEnergyUsage: Identifiable {
    let id: String
    let name: String
    /// CPU load normalized against total core count, 0-100. This is a proxy for
    /// energy impact, not a true joules measurement — real "Energy Impact" needs
    /// the private IOReport framework, which isn't wired up here.
    let percent: Double
}

/// Ranks running *applications* (not every daemon/CLI process) by CPU usage,
/// since there's no public API for per-app energy impact. `powermetrics` would
/// give real numbers but refuses to run without root, which isn't something a
/// menu bar app should ask for.
@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var topApps: [AppEnergyUsage] = []

    private var timer: Timer?
    private let coreCount = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        // NSWorkspace needs the main actor — snapshot the pid -> app-name map
        // here, before hopping off to sample `top` on a background thread.
        let appNames: [pid_t: String] = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
                guard let name = app.localizedName else { return nil }
                return (app.processIdentifier, name)
            },
            uniquingKeysWith: { first, _ in first }
        )

        Task.detached(priority: .utility) { [coreCount] in
            let apps = Self.sampleTopProcesses(coreCount: coreCount, appNames: appNames)
            await MainActor.run { [weak self] in
                self?.topApps = apps
            }
        }
    }

    private nonisolated static func sampleTopProcesses(
        coreCount: Double,
        appNames: [pid_t: String]
    ) -> [AppEnergyUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // `-l 2`: top computes %CPU as a delta between samples, so a single
        // sample (`-l 1`) has nothing to diff against and reports 0.0 for
        // every process. Two samples (~1s apart) give real numbers; we keep
        // only the second, accurate one.
        process.arguments = ["-l", "2", "-o", "cpu", "-n", "40", "-stats", "pid,cpu"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let lines = output.components(separatedBy: "\n")
        guard let lastHeaderIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PID") }) else {
            return []
        }

        var cpuByPid: [pid_t: Double] = [:]
        for line in lines[(lastHeaderIndex + 1)...] {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = pid_t(fields[0]), let cpu = Double(fields[1]) else { continue }
            cpuByPid[pid] = cpu
        }

        var results: [AppEnergyUsage] = []
        for (pid, name) in appNames {
            guard let cpu = cpuByPid[pid] else { continue }
            results.append(AppEnergyUsage(id: String(pid), name: name, percent: min(cpu / coreCount, 100)))
        }

        return results.sorted { $0.percent > $1.percent }
    }
}
