import Foundation

/// Builds the auth payload for gateway WebSocket handshake.
/// The payload is a pipe-delimited string that gets signed with Ed25519.
enum GatewayDeviceAuthPayload {

    /// Build a v2 payload string for signing.
    /// v2 format: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
    static func buildV2(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int,
        token: String?,
        nonce: String
    ) -> String {
        let scopeString = scopes.joined(separator: ",")
        let authToken = token ?? ""
        return [
            "v2",
            deviceId,
            clientId,
            clientMode,
            role,
            scopeString,
            String(signedAtMs),
            authToken,
            nonce,
        ].joined(separator: "|")
    }

    /// Build a v3 payload string for signing (requires gateway v3 support).
    /// v3 format: v2 fields + |platform|deviceFamily
    static func buildV3(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int,
        token: String?,
        nonce: String,
        platform: String?,
        deviceFamily: String?
    ) -> String {
        let scopeString = scopes.joined(separator: ",")
        let authToken = token ?? ""
        let normalizedPlatform = normalizeMetadataField(platform)
        let normalizedDeviceFamily = normalizeMetadataField(deviceFamily)
        return [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopeString,
            String(signedAtMs),
            authToken,
            nonce,
            normalizedPlatform,
            normalizedDeviceFamily,
        ].joined(separator: "|")
    }

    /// Build the signed device dictionary for the connect request.
    static func signedDeviceDictionary(
        payload: String,
        identity: DeviceIdentity,
        signedAtMs: Int,
        nonce: String
    ) -> [String: AnyCodable]? {
        guard let signature = DeviceIdentityManager.signPayload(payload, identity: identity),
              let publicKey = DeviceIdentityManager.publicKeyBase64Url(identity)
        else {
            return nil
        }
        return [
            "id": AnyCodable(identity.deviceId),
            "publicKey": AnyCodable(publicKey),
            "signature": AnyCodable(signature),
            "signedAt": AnyCodable(signedAtMs),
            "nonce": AnyCodable(nonce),
        ]
    }

    // MARK: - Private

    /// Lowercase ASCII A-Z only, matching cross-runtime normalization (TS/Swift/Kotlin).
    static func normalizeMetadataField(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var output = String()
        output.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            let codePoint = scalar.value
            if codePoint >= 65, codePoint <= 90, let lowered = UnicodeScalar(codePoint + 32) {
                output.unicodeScalars.append(lowered)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }
}
