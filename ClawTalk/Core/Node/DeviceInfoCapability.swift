import Foundation
import UIKit

enum DeviceInfoCapability {

    struct Info: Encodable {
        let deviceName: String
        let model: String
        let systemName: String
        let systemVersion: String
        let appVersion: String
        let buildNumber: String
        let bundleId: String
        let screenWidth: Int
        let screenHeight: Int
        let screenScale: CGFloat
        let locale: String
        let timezone: String
    }

    struct Status: Encodable {
        let batteryLevel: Float
        let batteryState: String
        let thermalState: String
        let systemUptime: TimeInterval
        let locale: String
        let timezone: String
        let timezoneOffset: Int
    }

    @MainActor
    static func getInfo() -> Info {
        let device = UIDevice.current
        let screen = UIScreen.main
        let bundle = Bundle.main

        return Info(
            deviceName: device.name,
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            bundleId: bundle.bundleIdentifier ?? "unknown",
            screenWidth: Int(screen.bounds.width),
            screenHeight: Int(screen.bounds.height),
            screenScale: screen.scale,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }

    @MainActor
    static func getStatus() async -> Status {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryState: String = switch device.batteryState {
        case .unknown: "unknown"
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        @unknown default: "unknown"
        }

        let thermalState: String = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }

        return Status(
            batteryLevel: device.batteryLevel,
            batteryState: batteryState,
            thermalState: thermalState,
            systemUptime: ProcessInfo.processInfo.systemUptime,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            timezoneOffset: TimeZone.current.secondsFromGMT() / 60
        )
    }
}
