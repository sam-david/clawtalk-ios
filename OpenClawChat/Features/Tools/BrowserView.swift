import SwiftUI

struct BrowserView: View {
    @Bindable var viewModel: ToolsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status section
                Section {
                    if let status = viewModel.browserStatusText {
                        JSONPrettyView(jsonString: status)
                    }

                    Button(action: {
                        Task { await viewModel.getBrowserStatus() }
                    }) {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Label("Status", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // Screenshot section
                Section {
                    if let screenshot = viewModel.browserScreenshot {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }

                    Button(action: {
                        Task { await viewModel.takeBrowserScreenshot() }
                    }) {
                        Label("Take Screenshot", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.openClawRed)
                } header: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()

                // Tabs section
                Section {
                    if let tabs = viewModel.browserTabsText {
                        JSONPrettyView(jsonString: tabs)
                    }

                    Button(action: {
                        Task { await viewModel.getBrowserTabs() }
                    }) {
                        Label("List Tabs", systemImage: "square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Label("Tabs", systemImage: "square.on.square")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .padding()
        }
        .navigationTitle("Browser")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .task {
            await viewModel.getBrowserStatus()
        }
    }
}
