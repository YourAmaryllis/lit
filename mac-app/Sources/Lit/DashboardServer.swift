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
    private let dashboardHTML: String
    private var listener: NWListener?

    init(
        battery: BatteryMonitor,
        alerts: AlertsManager,
        peripherals: PeripheralsMonitor,
        appearance: AppearanceSettings,
        energy: EnergyMonitor
    ) {
        self.battery = battery
        self.alerts = alerts
        self.peripherals = peripherals
        self.appearance = appearance
        self.energy = energy
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
            "devices": peripherals.devices.map {
                ["id": $0.id, "name": $0.name, "batteryPercent": $0.batteryPercent] as [String: Any]
            },
            "alerts": ["thresholds": alerts.thresholds] as [String: Any],
            "appearance": ["iconStyle": appearance.iconStyle.rawValue] as [String: Any],
            "energy": energy.topApps.map {
                ["id": $0.id, "name": $0.name, "percent": $0.percent, "watts": $0.watts] as [String: Any]
            },
        ]

        let sanitized = sanitizeForJSON(payload)
        return (try? JSONSerialization.data(withJSONObject: sanitized)) ?? Data("{}".utf8)
    }

    /// JSONSerialization chokes on Optional<Any> values wrapping nil — normalize to NSNull recursively.
    private func sanitizeForJSON(_ value: Any?) -> Any {
        switch value {
        case .none:
            return NSNull()
        case .some(let unwrapped):
            if let dict = unwrapped as? [String: Any?] {
                var result: [String: Any] = [:]
                for (key, nested) in dict {
                    result[key] = sanitizeForJSON(nested)
                }
                return result
            }
            if let array = unwrapped as? [Any] {
                return array.map { sanitizeForJSON($0) }
            }
            return unwrapped
        }
    }

    private static func loadDashboardHTML() -> String {
        if let url = Bundle.main.url(forResource: "dashboard", withExtension: "html"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        return "<html><body><h1>lit dashboard</h1><p>dashboard.html was not found in the app bundle's Resources.</p></body></html>"
    }
}
