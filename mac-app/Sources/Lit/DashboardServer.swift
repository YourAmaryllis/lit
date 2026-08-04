import Foundation
import Network

/// Serves the full battery dashboard (stats + settings) over plain HTTP on
/// loopback only — same pattern local-admin-page tools like CloudMount use.
/// The menu bar dropdown shows the same stats natively for a quick glance;
/// this is the same information with room to breathe, plus the two bits of
/// config (alert thresholds, icon style) that don't belong crammed into a
/// 300px popover.
@MainActor
final class DashboardServer {
    let port: UInt16 = 7091

    private let battery: BatteryMonitor
    private let alerts: AlertsManager
    private let peripherals: PeripheralsMonitor
    private let appearance: AppearanceSettings
    private let energy: EnergyMonitor
    private let temperature: SystemTemperatureMonitor
    private let dashboardHTML: String
    private var listener: NWListener?

    init(
        battery: BatteryMonitor,
        alerts: AlertsManager,
        peripherals: PeripheralsMonitor,
        appearance: AppearanceSettings,
        energy: EnergyMonitor,
        temperature: SystemTemperatureMonitor
    ) {
        self.battery = battery
        self.alerts = alerts
        self.peripherals = peripherals
        self.appearance = appearance
        self.energy = energy
        self.temperature = temperature
        self.dashboardHTML = Self.loadDashboardHTML()
    }

    var url: URL {
        URL(string: "http://127.0.0.1:\(port)/")!
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in self?.handle(connection: connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                var buffer = buffer
                if let data, !data.isEmpty {
                    buffer.append(data)
                }

                if let request = HTTPRequestParser.parse(buffer) {
                    self.respond(to: request, on: connection)
                    return
                }

                if isComplete || error != nil {
                    connection.cancel()
                    return
                }

                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let response: HTTPResponseData

        switch (request.method, request.path) {
        case ("GET", "/"):
            response = .html(dashboardHTML)
        case ("GET", "/api/status"):
            response = .json(statusJSON())
        case ("POST", "/api/thresholds/add"):
            if let value = request.jsonBody?["value"] as? Int {
                alerts.addThreshold(value)
            }
            response = .json(statusJSON())
        case ("POST", "/api/thresholds/remove"):
            if let value = request.jsonBody?["value"] as? Int {
                alerts.removeThreshold(value)
            }
            response = .json(statusJSON())
        case ("POST", "/api/icon-style"):
            if let raw = request.jsonBody?["style"] as? String, let style = MenuBarIconStyle(rawValue: raw) {
                appearance.iconStyle = style
            }
            response = .json(statusJSON())
        case ("POST", "/api/android-enabled"):
            if let enabled = request.jsonBody?["enabled"] as? Bool {
                peripherals.androidEnabled = enabled
                peripherals.refresh()
            }
            response = .json(statusJSON())
        case ("POST", "/api/health/refresh"):
            battery.refreshHealthNow()
            response = .json(statusJSON())
        default:
            response = .notFound
        }

        connection.send(content: response.rawHTTPResponse(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusJSON() -> Data {
        let payload: [String: Any?] = [
            "percentage": battery.percentage,
            "isPluggedIn": battery.isPluggedIn,
            "isCharging": battery.isCharging,
            "isFullyCharged": battery.isFullyCharged,
            "timeToEmptyMinutes": battery.timeToEmptyMinutes,
            "timeToFullMinutes": battery.timeToFullMinutes,
            "health": [
                "percentage": battery.healthPercentage,
                "condition": battery.healthCondition?.rawValue,
                "cycleCount": battery.cycleCount,
                "temperatureCelsius": battery.temperatureCelsius,
                "temperatureFahrenheit": battery.temperatureFahrenheit,
                "temperatureNormal": battery.isTemperatureNormal,
            ] as [String: Any?],
            "capacity": [
                "designMah": battery.designCapacityMah,
                "fullMah": battery.fullCapacityMah,
                "remainingMah": battery.remainingCapacityMah,
            ] as [String: Any?],
            "electrical": [
                "voltage": battery.voltageVolts,
                "amperageMilliamps": battery.amperageMilliamps,
                "wattage": battery.batteryWattage,
                "adapterWattage": battery.adapterWattage,
                "estimatedSystemWattage": battery.estimatedSystemWattageWhileCharging,
            ] as [String: Any?],
            "lastHealthUpdate": battery.lastHealthUpdate.map { $0.timeIntervalSince1970 },
            "systemTemperature": [
                "cpuCelsius": temperature.cpuTemperatureCelsius,
                "gpuCelsius": temperature.gpuTemperatureCelsius,
                "thermalPressure": temperature.thermalPressure.rawValue,
            ] as [String: Any?],
            "devices": peripherals.devices.map {
                [
                    "id": $0.id,
                    "name": $0.name,
                    "batteryPercent": $0.batteryPercent,
                    "isCharging": $0.isCharging as Any,
                    "symbolOverride": $0.symbolOverride as Any,
                ] as [String: Any]
            },
            "alerts": ["thresholds": alerts.thresholds] as [String: Any],
            "appearance": ["iconStyle": appearance.iconStyle.rawValue] as [String: Any],
            "android": ["enabled": peripherals.androidEnabled] as [String: Any],
            "energy": energy.topApps.map {
                ["id": $0.id, "name": $0.name, "percent": $0.percent, "watts": $0.watts] as [String: Any]
            },
        ]

        let sanitized = sanitizeForJSON(payload)
        return (try? JSONSerialization.data(withJSONObject: sanitized)) ?? Data("{}".utf8)
    }

    /// JSONSerialization chokes on Optional<Any> values wrapping nil — normalize
    /// to NSNull recursively. Uses reflection (rather than casting to a specific
    /// `[String: Any?]` vs `[String: Any]` shape) so this is correct regardless
    /// of how a nested Optional<T> value (e.g. Bool?, String?) ended up boxed as
    /// Any inside a dictionary — which shape you get depends on exactly how the
    /// dictionary literal was typed at the call site, and getting that wrong
    /// silently produces a value JSONSerialization can't encode.
    private func sanitizeForJSON(_ value: Any?) -> Any {
        guard let value else { return NSNull() }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let unwrapped = mirror.children.first?.value else { return NSNull() }
            return sanitizeForJSON(unwrapped)
        }

        if let dict = value as? [String: Any?] {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                result[key] = sanitizeForJSON(nested)
            }
            return result
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                result[key] = sanitizeForJSON(nested)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { sanitizeForJSON($0) }
        }
        return value
    }

    private static func loadDashboardHTML() -> String {
        if let url = Bundle.main.url(forResource: "dashboard", withExtension: "html"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        return "<html><body><h1>lit dashboard</h1><p>dashboard.html was not found in the app bundle's Resources.</p></body></html>"
    }
}
