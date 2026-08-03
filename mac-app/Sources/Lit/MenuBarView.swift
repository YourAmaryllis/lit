import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var alerts: AlertsManager
    @ObservedObject var peripherals: PeripheralsMonitor
    @State private var newThresholdText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(battery.percentage)%")
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                if let health = battery.healthPercentage {
                    GridRow {
                        Text("Battery Health")
                        Text("\(health)%").fontWeight(.medium)
                    }
                }
                if let cycles = battery.cycleCount {
                    GridRow {
                        Text("Cycle Count")
                        Text("\(cycles)").fontWeight(.medium)
                    }
                }
                if let temp = battery.temperatureCelsius {
                    GridRow {
                        Text("Temperature")
                        Text(String(format: "%.1f\u{00B0}C", temp)).fontWeight(.medium)
                    }
                }
                if let minutes = remainingMinutes, minutes > 0 {
                    GridRow {
                        Text(battery.isCharging ? "Time to Full" : "Time Remaining")
                        Text("\(minutes / 60)h \(minutes % 60)m").fontWeight(.medium)
                    }
                }
            }

            if !peripherals.devices.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Devices")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(peripherals.devices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Text("\(device.batteryPercent)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Alert me at")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(alerts.thresholds, id: \.self) { threshold in
                    HStack {
                        Text("\(threshold)%")
                        Spacer()
                        Button {
                            alerts.removeThreshold(threshold)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("%", text: $newThresholdText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Button("Add") {
                        if let value = Int(newThresholdText) {
                            alerts.addThreshold(value)
                        }
                        newThresholdText = ""
                    }
                }
            }

            Divider()

            Button("Quit lit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var statusLabel: String {
        if battery.isPluggedIn {
            return battery.isCharging ? "Charging" : "Plugged In"
        }
        return "On Battery"
    }

    private var remainingMinutes: Int? {
        battery.isCharging ? battery.timeToFullMinutes : battery.timeToEmptyMinutes
    }
}
