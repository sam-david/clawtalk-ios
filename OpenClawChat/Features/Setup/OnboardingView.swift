import SwiftUI

struct OnboardingView: View {
    @Bindable var settingsStore: SettingsStore
    let onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var gatewayURL = ""
    @State private var gatewayToken = ""
    @State private var connectionState: ConnectionTestState = .idle
    @State private var modelManager = WhisperModelManager.shared

    enum Step: CaseIterable {
        case welcome
        case gatewaySetup
        case gateway
        case connectionTest
        case voice
    }

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(Array(Step.allCases.enumerated()), id: \.offset) { index, s in
                    Circle()
                        .fill(s == step ? Color.openClawRed : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            .padding(.top, 16)

            switch step {
            case .welcome:
                welcomeStep
            case .gatewaySetup:
                gatewaySetupStep
            case .gateway:
                gatewayStep
            case .connectionTest:
                connectionTestStep
            case .voice:
                voiceStep
            }
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Text("Welcome to ClawTalk")
                .font(.title)
                .fontWeight(.bold)

            Text("Voice and text chat with your\nOpenClaw AI agents.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton("Get Started") {
                withAnimation { step = .gatewaySetup }
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Gateway Setup Instructions

    private var gatewaySetupStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("Gateway Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("ClawTalk connects to an OpenClaw gateway running on your computer or server.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                bulletPoint("Install OpenClaw on your machine")
                bulletPoint("Run openclaw onboard to configure")
                bulletPoint("Enable the HTTP API in gateway config")
                bulletPoint("Set a gateway auth token")
                bulletPoint("Expose over HTTPS for remote access")
            }
            .padding(.horizontal, 32)

            Link(destination: URL(string: "https://openclaw.com/docs/gateway/configuration")!) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                    Text("View Setup Guide")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.openClawRed)
            }
            .padding(.top, 4)

            Spacer()

            primaryButton("I Have a Gateway") {
                withAnimation { step = .gateway }
            }

            Button("I'll set this up later") {
                withAnimation { step = .voice }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 48)
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.openClawRed)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Gateway Config

    private var gatewayStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("Connect to Gateway")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter your OpenClaw gateway URL and access token.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gateway URL")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Gateway URL", text: $gatewayURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gateway Token")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    SecureField("Your access token", text: $gatewayToken)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            primaryButton("Test Connection") {
                settingsStore.settings.gatewayURL = gatewayURL
                settingsStore.gatewayToken = gatewayToken
                settingsStore.save()
                withAnimation { step = .connectionTest }
                testConnection()
            }
            .disabled(gatewayURL.isEmpty || gatewayToken.isEmpty)
            .opacity(gatewayURL.isEmpty || gatewayToken.isEmpty ? 0.5 : 1)

            Button("Skip") {
                settingsStore.settings.gatewayURL = gatewayURL
                settingsStore.gatewayToken = gatewayToken
                settingsStore.save()
                withAnimation { step = .voice }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Connection Test

    private var connectionTestStep: some View {
        VStack(spacing: 24) {
            Spacer()

            switch connectionState {
            case .idle, .testing:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.openClawRed)

                Text("Testing Connection...")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Connecting to your gateway")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Connected!")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Your gateway is reachable and authenticated.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)

                Text("Connection Failed")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            switch connectionState {
            case .idle, .testing:
                EmptyView()
            case .success:
                primaryButton("Continue") {
                    withAnimation { step = .voice }
                }
                .padding(.bottom, 48)
            case .failed:
                primaryButton("Retry") {
                    testConnection()
                }

                Button("Go Back") {
                    connectionState = .idle
                    withAnimation { step = .gateway }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button("Continue Anyway") {
                    withAnimation { step = .voice }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Voice Setup

    private var voiceStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed)

            Text("Voice Setup")
                .font(.title2)
                .fontWeight(.bold)

            Text("ClawTalk uses an on-device speech model for private voice transcription. Audio never leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                Text(settingsStore.settings.whisperModelSize.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if modelManager.isDownloading {
                    ProgressView(value: modelManager.downloadProgress)
                        .tint(.openClawRed)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    Text("Downloading... \(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = modelManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.top, 8)

            Spacer()

            if modelManager.isDownloading {
                Button("Continue Without Voice") {
                    finishOnboarding()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 48)
            } else if modelManager.hasDownloadedModel {
                primaryButton("Done") {
                    finishOnboarding()
                }
                .padding(.bottom, 48)
            } else {
                primaryButton("Download Model") {
                    Task {
                        await modelManager.downloadModel(size: settingsStore.settings.whisperModelSize)
                        if modelManager.isModelReady {
                            finishOnboarding()
                        }
                    }
                }

                Button("Skip Voice Setup") {
                    settingsStore.settings.voiceInputEnabled = false
                    settingsStore.save()
                    finishOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Helpers

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.openClawRed)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private func testConnection() {
        connectionState = .testing

        Task {
            do {
                let baseURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: "\(baseURL)/v1/models") else {
                    connectionState = .failed("Invalid gateway URL")
                    return
                }

                var request = URLRequest(url: url)
                request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15

                let (_, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200...299:
                        connectionState = .success
                    case 401, 403:
                        connectionState = .failed("Authentication failed. Check your gateway token.")
                    case 404:
                        // /v1/models may not exist but the gateway responded, that's OK
                        connectionState = .success
                    default:
                        connectionState = .failed("Gateway returned HTTP \(http.statusCode)")
                    }
                } else {
                    connectionState = .failed("Unexpected response from gateway")
                }
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet:
                    connectionState = .failed("No internet connection")
                case .timedOut:
                    connectionState = .failed("Connection timed out. Check the URL and make sure the gateway is running.")
                case .cannotFindHost, .cannotConnectToHost:
                    connectionState = .failed("Cannot reach gateway. Check the URL.")
                case .secureConnectionFailed:
                    connectionState = .failed("SSL/TLS connection failed. Make sure the gateway uses HTTPS.")
                default:
                    connectionState = .failed(error.localizedDescription)
                }
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func finishOnboarding() {
        settingsStore.hasCompletedOnboarding = true
        settingsStore.save()
        onComplete()
    }
}
