import SwiftUI

struct ToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ToolsViewModel

    init(settings: SettingsStore, gatewayConnection: GatewayConnection? = nil) {
        _viewModel = State(initialValue: ToolsViewModel(settings: settings, gatewayConnection: gatewayConnection))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    toolRow(.memory, label: "Memory", icon: "brain.head.profile") {
                        MemorySearchView(viewModel: viewModel)
                    }

                    toolRow(.agents, label: "Agents", icon: "cpu") {
                        AgentsView(viewModel: viewModel)
                    }

                    toolRow(.sessions, label: "Sessions", icon: "list.bullet.rectangle") {
                        SessionsView(viewModel: viewModel)
                    }

                    toolRow(.browser, label: "Browser", icon: "globe") {
                        BrowserView(viewModel: viewModel)
                    }

} header: {
                    Text("Agent Tools")
                } footer: {
                    Text("Interact directly with your agent's tools without going through chat.")
                }

                Section {
                    toolRow(.models, label: "Models", icon: "sparkles") {
                        ModelsView(viewModel: viewModel)
                    }
                } header: {
                    Text("Gateway Info")
                } footer: {
                    if !viewModel.isAvailable(.models) {
                        Text("Enable WebSocket mode in Settings to browse available models.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await viewModel.checkAvailability()
            }
        }
    }

    @ViewBuilder
    private func toolRow<Destination: View>(
        _ category: ToolsViewModel.ToolCategory,
        label: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        let available = viewModel.isAvailable(category)

        if available {
            NavigationLink {
                destination()
            } label: {
                Label(label, systemImage: icon)
                    .foregroundStyle(Color.openClawRed)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    Text(category == .models ? "Requires WebSocket connection" : "Not enabled on gateway")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
            .foregroundStyle(.secondary)
        }
    }
}
