import SwiftUI
import AppKit

@main
struct LitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(battery: appDelegate.battery, dashboardURL: appDelegate.dashboardServer.url)
        } label: {
            MenuBarLabel(battery: appDelegate.battery, appearance: appDelegate.appearance)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        HStack(spacing: 3) {
            if appearance.iconStyle != .percentageOnly {
                Image(systemName: BatteryIcon.symbolName(forPercentage: battery.percentage))
                    .foregroundStyle(BatteryIcon.color(forPercentage: battery.percentage, isPluggedIn: battery.isPluggedIn))
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            }
            if appearance.iconStyle != .iconOnly {
                Text("\(battery.percentage)%")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let battery = BatteryMonitor()
    let alerts = AlertsManager()
    let peripherals = PeripheralsMonitor()
    let appearance = AppearanceSettings()
    let energy = EnergyMonitor()
    lazy var dashboardServer = DashboardServer(
        battery: battery,
        alerts: alerts,
        peripherals: peripherals,
        appearance: appearance,
        energy: energy
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        battery.onUpdate = { [alerts] percentage, isPluggedIn, isCharging in
            alerts.evaluate(percentage: percentage, isPluggedIn: isPluggedIn, isCharging: isCharging)
        }
        dashboardServer.start()
    }
}
