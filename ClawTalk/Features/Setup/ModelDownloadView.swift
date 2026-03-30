import SwiftUI

struct ModelDownloadView: View {
    let modelSize: WhisperModelSize
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var manager = WhisperModelManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
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
                Text(modelSize.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if manager.isDownloading {
                    ProgressView(value: manager.downloadProgress)
                        .tint(.openClawRed)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    Text("Downloading... \(Int(manager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = manager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if manager.isDownloading {
                    // Show cancel-like skip while downloading
                    Button("Continue Without Voice") {
                        onSkip()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button(action: {
                        Task {
                            await manager.downloadModel(size: modelSize)
                            if manager.isModelReady {
                                onComplete()
                            }
                        }
                    }) {
                        Text("Download Model")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.openClawRed)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Button("Skip for Now") {
                        onSkip()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}
