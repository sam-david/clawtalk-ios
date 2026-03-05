import Foundation
import SwiftUI

@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let settingsKey = "app_settings"
    private let secure = SecureStorage.shared

    var settings: AppSettings {
        didSet { save() }
    }

    // Proxy properties for secure credentials (not in UserDefaults)
    var gatewayToken: String {
        get { secure.gatewayToken ?? "" }
        set { secure.gatewayToken = newValue.isEmpty ? nil : newValue }
    }

    var elevenLabsAPIKey: String {
        get { secure.elevenLabsAPIKey ?? "" }
        set { secure.elevenLabsAPIKey = newValue.isEmpty ? nil : newValue }
    }

    var openAIAPIKey: String {
        get { secure.openAIAPIKey ?? "" }
        set { secure.openAIAPIKey = newValue.isEmpty ? nil : newValue }
    }

    var isConfigured: Bool {
        !settings.gatewayURL.isEmpty && !gatewayToken.isEmpty
    }

    init() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}
