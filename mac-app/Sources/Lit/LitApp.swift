import SwiftUI
import AppKit

@main
struct LitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(battery: appDelegate.battery, alerts: appDelegate.alerts, peripherals: appDelegate.peripherals)
        } label: {
            MenuBarLabel(battery: appDelegate.battery)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        Text(battery.menuBarLabel)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let battery = BatteryMonitor()
    let alerts = AlertsManager()
    let peripherals = PeripheralsMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        battery.onUpdate = { [alerts] percentage, isPluggedIn in
            alerts.evaluate(percentage: percentage, isPluggedIn: isPluggedIn)
        }
    }
}
