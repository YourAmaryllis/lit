import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var alerts: AlertsManager
    @ObservedObject var peripherals: PeripheralsMonitor
    @ObservedObject var appearance: AppearanceSettings
    @State private var newThresholdText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            statsGrid

            if !peripherals.devices.isEmpty {
                Divider()
                devicesSection
            }

            Divider()

            alertsSection

            Divider()

            iconStylePicker

            Divider()

            Button("Quit lit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var header: some View {
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
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            if let health = battery.healthPercentage {
                GridRow {
                    Label("Battery Health", systemImage: "heart.text.square")
                    Text("\(health)%").fontWeight(.medium).gridColumnAlignment(.trailing)
                }
            }
            if let cycles = battery.cycleCount {
                GridRow {
                    Label("Cycle Count", systemImage: "arrow.triangle.2.circlepath")
                    Text("\(cycles)").fontWeight(.medium)
                }
            }
            if let temp = battery.temperatureCelsius {
                GridRow {
                    Label("Temperature", systemImage: "thermometer.medium")
                    Text(String(format: "%.1f\u{00B0}C", temp)).fontWeight(.medium)
                }
            }
            if let minutes = remainingMinutes, minutes > 0 {
                GridRow {
                    Label(battery.isCharging ? "Time to Full" : "Time Remaining", systemImage: "clock")
                    Text("\(minutes / 60)h \(minutes % 60)m").fontWeight(.medium)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .labelStyle(.titleAndIcon)
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Devices")
            ForEach(peripherals.devices) { device in
                HStack {
                    Image(systemName: BatteryIcon.symbolName(forPercentage: device.batteryPercent))
                        .foregroundStyle(BatteryIcon.color(forPercentage: device.batteryPercent, isPluggedIn: false))
                        .frame(width: 18)
                    Text(device.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(device.batteryPercent)%")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Alert me at")
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
                .font(.subheadline)
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
    }

    private var iconStylePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Menu Bar Icon")
            Picker("", selection: $appearance.iconStyle) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
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
