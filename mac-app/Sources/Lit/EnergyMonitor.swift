import Foundation

struct AppEnergyUsage: Identifiable {
    let id: String
    let name: String
    /// CPU load normalized against total core count, 0-100. This is a proxy for
    /// energy impact, not a true joules measurement — real "Energy Impact" needs
    /// the private IOReport framework, which isn't wired up here.
    let percent: Double
}

/// Ranks running processes by CPU usage via `top`, since there's no public API
/// for per-app energy impact. `powermetrics` would give real numbers but refuses
/// to run without root, which isn't something a menu bar app should ask for.
@MainActor
final class EnergyMonitor: ObservableObject {
    @Published private(set) var topApps: [AppEnergyUsage] = []

    private var timer: Timer?
    private let coreCount = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) { [coreCount] in
            let apps = Self.sampleTopProcesses(coreCount: coreCount)
            await MainActor.run { [weak self] in
                self?.topApps = apps
            }
        }
    }

    private nonisolated static func sampleTopProcesses(coreCount: Double) -> [AppEnergyUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "1", "-o", "cpu", "-n", "8", "-stats", "pid,command,cpu"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [AppEnergyUsage] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = fields.first, Int(pid) != nil,
                  let cpu = Double(fields.last ?? "")
            else { continue }

            let name = fields[1..<(fields.count - 1)].joined(separator: " ")
            let normalized = min((cpu / coreCount), 100)
            results.append(AppEnergyUsage(id: String(pid), name: name, percent: normalized))
        }

        return results.sorted { $0.percent > $1.percent }
    }
}
