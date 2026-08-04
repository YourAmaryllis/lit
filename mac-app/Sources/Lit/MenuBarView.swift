import SwiftUI
import AppKit

/// Deliberately minimal — a glance and a way out to the full dashboard, not
/// a place to cram every stat into a 280px popover.
struct MenuBarView: View {
    @ObservedObject var battery: BatteryMonitor
    let dashboardURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: BatteryIcon.symbolName(forPercentage: battery.percentage))
                    .font(.system(size: 26))
                    .foregroundStyle(BatteryIcon.color(forPercentage: battery.percentage, isPluggedIn: battery.isPluggedIn))
                Text("\(battery.percentage)%")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                NSWorkspace.shared.open(dashboardURL)
            } label: {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("Open Dashboard")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button("Quit lit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    private var statusLabel: String {
        if battery.isPluggedIn {
            return battery.isCharging ? "Charging" : "Plugged In"
        }
        return "On Battery"
    }
}
