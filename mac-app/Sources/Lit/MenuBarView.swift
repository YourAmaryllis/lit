import SwiftUI
import AppKit

/// The rich, at-a-glance view — same information density as Juicy's own
/// dropdown, with collapsible sections and color-coded status. Alert
/// thresholds and icon style are the only things that live web-side instead
/// (see the "Settings" row at the bottom); everything here is read-only.
struct MenuBarView: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var peripherals: PeripheralsMonitor
    @ObservedObject var energy: EnergyMonitor
    @ObservedObject var temperature: SystemTemperatureMonitor
    let dashboardURL: URL

    @State private var expanded: Set<String> = ["health", "power", "capacity", "energy"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                batteryInfoSection
                powerSection
                capacitySection
                if temperature.cpuTemperatureCelsius != nil || temperature.gpuTemperatureCelsius != nil {
                    systemTemperatureSection
                }
                if !peripherals.devices.isEmpty {
                    devicesSection
                }
                energySection
                Divider()
                settingsRow
                quitButton
            }
            .padding(16)
        }
        .frame(width: 300, height: 580)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(battery.percentage) / 100)
                    .stroke(
                        BatteryIcon.color(forPercentage: battery.percentage, isPluggedIn: battery.isPluggedIn),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(battery.percentage)%")
                    .font(.system(size: 17, weight: .bold))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusLabel).font(.headline)
                Text(subLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusLabel: String {
        if battery.isPluggedIn {
            if battery.isCharging { return "Charging" }
            return battery.isFullyCharged ? "Fully Charged" : "Plugged In"
        }
        return "On Battery"
    }

    private var subLabel: String {
        if battery.isCharging, let minutes = positiveMinutes(battery.timeToFullMinutes) {
            return "\(formatMinutes(minutes)) until full"
        }
        if !battery.isPluggedIn, let minutes = positiveMinutes(battery.timeToEmptyMinutes) {
            return "\(formatMinutes(minutes)) remaining"
        }
        return battery.isFullyCharged ? "Ready to unplug" : " "
    }

    // MARK: Battery Information

    private var batteryInfoSection: some View {
        DisclosureGroup(isExpanded: binding("health")) {
            VStack(alignment: .leading, spacing: 12) {
                if let health = battery.healthPercentage, let condition = battery.healthCondition {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(health)%")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(conditionColor(condition))
                            Text(condition.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(conditionColor(condition))
                            Spacer()
                            if let cycles = battery.cycleCount {
                                Text("\(cycles) cycles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ProgressView(value: Double(health), total: 100)
                            .tint(conditionColor(condition))
                    }
                }

                if let temp = battery.temperatureCelsius, let tempF = battery.temperatureFahrenheit {
                    HStack {
                        Text(String(format: "%.1f\u{00B0}C / %.1f\u{00B0}F", temp, tempF))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let normal = battery.isTemperatureNormal {
                            Label(normal ? "Normal" : "Out of range", systemImage: normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(normal ? .green : .orange)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Battery Information", symbol: "heart.text.square.fill", color: .green)
        }
    }

    // MARK: Power & Electrical

    private var powerSection: some View {
        DisclosureGroup(isExpanded: binding("power")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    statPair(label: "Voltage", value: battery.voltageVolts.map { String(format: "%.2f V", $0) } ?? "\u{2014}")
                    Spacer()
                    statPair(label: "Current", value: battery.amperageMilliamps.map { "\($0) mA" } ?? "\u{2014}", trailing: true)
                }
                powerFlow
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Power & Electrical", symbol: "bolt.fill", color: .yellow)
        }
    }

    /// While actively charging, the adapter's power genuinely splits into two
    /// simultaneous destinations, so it's shown as a branch (one source, two
    /// rows) rather than a single left-to-right flow. Discharging and idle/full
    /// only ever have one real destination, so those stay a simple two-node row.
    @ViewBuilder
    private var powerFlow: some View {
        if battery.isPluggedIn && battery.isCharging {
            chargingSplitFlow
        } else {
            simpleFlow
        }
    }

    private var chargingSplitFlow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 3) {
                    Image(systemName: "powerplug.fill").font(.system(size: 18))
                    Text("Adapter").font(.caption2).foregroundStyle(.secondary)
                    if let watts = battery.adapterWattage {
                        Text("\(watts)W").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56)

                Divider().frame(height: 44)

                VStack(alignment: .leading, spacing: 10) {
                    flowBranchRow(
                        watts: battery.batteryWattage,
                        label: "to battery",
                        symbol: BatteryIcon.symbolName(forPercentage: battery.percentage)
                    )
                    flowBranchRow(
                        watts: battery.estimatedSystemWattageWhileCharging,
                        label: "to Mac",
                        symbol: "laptopcomputer",
                        isEstimate: true
                    )
                }

                Spacer(minLength: 0)
            }
            if battery.estimatedSystemWattageWhileCharging != nil {
                Text("Mac power is estimated (adapter rating minus battery draw) — only accurate when the adapter is near its limit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func flowBranchRow(watts: Double?, label: String, symbol: String, isEstimate: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let watts {
                Text("\(isEstimate ? "~" : "")\(String(format: "%.1f", watts))W \(label)")
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Text("\u{2014}").font(.caption).fontWeight(.medium)
            }
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var simpleFlow: some View {
        let watts = battery.batteryWattage ?? 0
        let flowing = abs(watts) > 0.05
        let leftSymbol = battery.isPluggedIn ? "powerplug.fill" : BatteryIcon.symbolName(forPercentage: battery.percentage)
        let leftLabel = battery.isPluggedIn ? "Adapter" : "Battery"
        let leftCaption = battery.isPluggedIn ? battery.adapterWattage.map { "\($0)W" } : nil
        let rightSymbol = battery.isPluggedIn ? BatteryIcon.symbolName(forPercentage: battery.percentage) : "laptopcomputer"
        let rightLabel = battery.isPluggedIn ? "Battery" : "Mac"

        return HStack(spacing: 8) {
            flowNode(symbol: leftSymbol, label: leftLabel, caption: leftCaption)
            VStack(spacing: 2) {
                Text(flowing ? String(format: "%.1f W", abs(watts)) : "Idle")
                    .font(.system(size: 14, weight: .bold))
                Text(flowCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            flowNode(symbol: rightSymbol, label: rightLabel, caption: nil)
        }
    }

    private func flowNode(symbol: String, label: String, caption: String?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 16))
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 56)
    }

    /// simpleFlow only renders for discharging or idle/full — the charging case
    /// (isPluggedIn && isCharging) is handled separately by chargingSplitFlow.
    private var flowCaption: String {
        if battery.isFullyCharged { return "Battery full" }
        if !battery.isPluggedIn { return "Discharging" }
        return "Idle"
    }

    // MARK: Capacity Details

    private var capacitySection: some View {
        DisclosureGroup(isExpanded: binding("capacity")) {
            VStack(alignment: .leading, spacing: 10) {
                capacityBar
                HStack {
                    capacityStat("Remaining", battery.remainingCapacityMah, color: .green)
                    Spacer()
                    capacityStat("Full", battery.fullCapacityMah, color: .blue)
                    Spacer()
                    capacityStat("Design", battery.designCapacityMah, color: .secondary)
                }
                HStack {
                    Text(lastUpdatedLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh now") {
                        battery.refreshHealthNow()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Capacity Details", symbol: "minus.plus.batteryblock.fill", color: .blue)
        }
    }

    private var capacityBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
                if let full = battery.fullCapacityMah, let design = battery.designCapacityMah, design > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.35))
                        .frame(width: geo.size.width * min(Double(full) / Double(design), 1))
                }
                if let remaining = battery.remainingCapacityMah, let design = battery.designCapacityMah, design > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * min(Double(remaining) / Double(design), 1))
                }
            }
        }
        .frame(height: 8)
    }

    private var lastUpdatedLabel: String {
        guard let date = battery.lastHealthUpdate else { return "Not yet updated" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Updated just now" }
        return "Updated \(seconds / 60)m ago"
    }

    // MARK: System Temperature

    private var systemTemperatureSection: some View {
        DisclosureGroup(isExpanded: binding("temperature")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let cpu = temperature.cpuTemperatureCelsius {
                        temperatureStat("CPU", celsius: cpu)
                    }
                    Spacer()
                    if let gpu = temperature.gpuTemperatureCelsius {
                        temperatureStat("GPU", celsius: gpu, trailing: true)
                    }
                }
                HStack {
                    Text("Thermal Pressure").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(temperature.thermalPressure.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(thermalPressureColor(temperature.thermalPressure))
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("System Temperature", symbol: "thermometer.medium", color: .red)
        }
    }

    private func temperatureStat(_ label: String, celsius: Double, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(String(format: "%.0f\u{00B0}C", celsius))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(temperatureColor(celsius))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius >= 90 { return .red }
        if celsius >= 75 { return .orange }
        return .primary
    }

    private func thermalPressureColor(_ pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }

    // MARK: Devices

    private var devicesSection: some View {
        DisclosureGroup(isExpanded: binding("devices")) {
            VStack(spacing: 8) {
                ForEach(peripherals.devices) { device in
                    HStack(spacing: 6) {
                        Image(systemName: device.symbolOverride ?? BatteryIcon.symbolName(forPercentage: device.batteryPercent))
                            .foregroundStyle(BatteryIcon.color(forPercentage: device.batteryPercent, isPluggedIn: false))
                            .frame(width: 18)
                        Text(device.name).font(.subheadline).lineLimit(1)
                        if device.isCharging == true {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Text("\(device.batteryPercent)%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Connected Devices", symbol: "cable.connector", color: .purple)
        }
    }

    // MARK: Apps Using Energy

    private var energySection: some View {
        DisclosureGroup(isExpanded: binding("energy")) {
            VStack(alignment: .leading, spacing: 10) {
                let apps = energy.topApps.filter { $0.percent >= 10 }.prefix(5)
                if apps.isEmpty {
                    Text("Nothing using significant energy right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(apps)) { app in
                        energyRow(app)
                    }
                }
                Text("Real energy usage from the kernel, as a % share of the total across every running app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    openActivityMonitor()
                } label: {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Open App Usage")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Apps Using Significant Energy", symbol: "bolt.fill", color: .orange)
        }
    }

    private func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.open(url)
        }
    }

    private func energyRow(_ app: AppEnergyUsage) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(avatarColor(for: app.name))
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)

            Text(app.name).font(.caption).lineLimit(1)
            Spacer()
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(energyBarColor(app.percent))
                    .frame(width: geo.size.width * min(app.percent / 100, 1), height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 60, height: 4)
            Text("\(Int(app.percent))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func energyBarColor(_ percent: Double) -> Color {
        if percent >= 40 { return .red }
        if percent >= 15 { return .yellow }
        return .green
    }

    private func avatarColor(for name: String) -> Color {
        let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .teal]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    // MARK: Settings / Quit

    private var settingsRow: some View {
        Button {
            NSWorkspace.shared.open(dashboardURL)
        } label: {
            HStack {
                sectionLabel("Settings", symbol: "gearshape.fill", color: .gray)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var quitButton: some View {
        Button("Quit lit") {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: Shared helpers

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(key) },
            set: { isExpanded in
                if isExpanded { expanded.insert(key) } else { expanded.remove(key) }
            }
        )
    }

    private func sectionLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 22, height: 22)
            Text(title).font(.subheadline).fontWeight(.semibold)
        }
    }

    private func conditionColor(_ condition: HealthCondition) -> Color {
        switch condition {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private func capacityStat(_ label: String, _ value: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { "\($0)" } ?? "\u{2014}")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func statPair(label: String, value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func positiveMinutes(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0, minutes != 65535 else { return nil }
        return minutes
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return (h > 0 ? "\(h)h " : "") + "\(m)m"
    }
}
