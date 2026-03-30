import Foundation

/// Persisted device auth token received from the gateway after handshake.
struct DeviceAuthEntry: Codable, Sendable {
    let token: String
    let role: String
    let scopes: [String]
    let updatedAtMs: Int
}

/// Stores/retrieves device auth tokens in the Keychain.
/// The gateway issues a device token on successful handshake that can be
/// reused for subsequent connections without re-authenticating with the
/// shared gateway token.
enum DeviceAuthTokenStore {

    private static let keyPrefix = "device_auth_"

    static func loadToken(deviceId: String, role: String, gatewayHost: String) -> DeviceAuthEntry? {
        let key = storeKey(deviceId: deviceId, role: role, gatewayHost: gatewayHost)
        guard let json = SecureStorage.shared.getString(key),
              let data = json.data(using: .utf8),
              let entry = try? JSONDecoder().decode(DeviceAuthEntry.self, from: data)
        else {
            return nil
        }
        return entry
    }

    static func storeToken(
        deviceId: String,
        role: String,
        gatewayHost: String,
        token: String,
        scopes: [String] = []
    ) {
        let entry = DeviceAuthEntry(
            token: token,
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            scopes: Array(Set(scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted(),
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        let key = storeKey(deviceId: deviceId, role: role, gatewayHost: gatewayHost)
        if let data = try? JSONEncoder().encode(entry),
           let json = String(data: data, encoding: .utf8) {
            SecureStorage.shared.setString(json, forKey: key)
        }
    }

    static func clearToken(deviceId: String, role: String, gatewayHost: String) {
        let key = storeKey(deviceId: deviceId, role: role, gatewayHost: gatewayHost)
        SecureStorage.shared.setString(nil, forKey: key)
    }

    private static func storeKey(deviceId: String, role: String, gatewayHost: String) -> String {
        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = gatewayHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(keyPrefix)\(deviceId)_\(normalizedRole)_\(normalizedHost)"
    }
}
