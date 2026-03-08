import CryptoKit
import Foundation

/// Ed25519 device identity for gateway authentication.
/// Device ID is derived from the SHA256 hash of the public key.
struct DeviceIdentity: Codable, Sendable {
    let deviceId: String
    let publicKey: String   // base64-encoded raw representation
    let privateKey: String  // base64-encoded raw representation
    let createdAtMs: Int
}

/// Manages device identity lifecycle — load from Keychain or generate a new one.
enum DeviceIdentityManager {

    private static let deviceIdKey = "ed25519_device_id"
    private static let publicKeyKey = "ed25519_public_key"
    private static let privateKeyKey = "ed25519_private_key"
    private static let createdAtKey = "ed25519_created_at"

    /// Load existing identity from Keychain, or generate and persist a new one.
    static func loadOrCreate() -> DeviceIdentity {
        let secure = SecureStorage.shared

        if let deviceId = secure.getString(deviceIdKey),
           let pubKey = secure.getString(publicKeyKey),
           let privKey = secure.getString(privateKeyKey),
           let createdStr = secure.getString(createdAtKey),
           let createdAt = Int(createdStr),
           !deviceId.isEmpty, !pubKey.isEmpty, !privKey.isEmpty {
            return DeviceIdentity(
                deviceId: deviceId,
                publicKey: pubKey,
                privateKey: privKey,
                createdAtMs: createdAt
            )
        }

        let identity = generate()
        save(identity)
        return identity
    }

    /// Sign a payload string with the device's Ed25519 private key.
    /// Returns a base64url-encoded signature, or nil on failure.
    static func signPayload(_ payload: String, identity: DeviceIdentity) -> String? {
        guard let privateKeyData = Data(base64Encoded: identity.privateKey) else { return nil }
        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
            let signature = try privateKey.signature(for: Data(payload.utf8))
            return base64UrlEncode(signature)
        } catch {
            return nil
        }
    }

    /// Return the public key in base64url encoding (for wire format).
    static func publicKeyBase64Url(_ identity: DeviceIdentity) -> String? {
        guard let data = Data(base64Encoded: identity.publicKey) else { return nil }
        return base64UrlEncode(data)
    }

    // MARK: - Private

    private static func generate() -> DeviceIdentity {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.rawRepresentation
        let privateKeyData = privateKey.rawRepresentation
        let deviceId = SHA256.hash(data: publicKeyData)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        return DeviceIdentity(
            deviceId: deviceId,
            publicKey: publicKeyData.base64EncodedString(),
            privateKey: privateKeyData.base64EncodedString(),
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func save(_ identity: DeviceIdentity) {
        let secure = SecureStorage.shared
        secure.setString(identity.deviceId, forKey: deviceIdKey)
        secure.setString(identity.publicKey, forKey: publicKeyKey)
        secure.setString(identity.privateKey, forKey: privateKeyKey)
        secure.setString(String(identity.createdAtMs), forKey: createdAtKey)
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
