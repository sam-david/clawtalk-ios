import SwiftUI

struct AddChannelView: View {
    var channelStore: ChannelStore
    var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var agentId = ""
    @State private var customAgentId = ""
    @State private var agents: [AgentEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let client = OpenClawClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel Name", text: $name)
                } header: {
                    Text("Name")
                }

                if !agents.isEmpty {
                    Section {
                        ForEach(agents) { agent in
                            Button(action: {
                                agentId = agent.agentId
                                customAgentId = ""
                                if name.isEmpty {
                                    name = agent.agentId.capitalized
                                }
                            }) {
                                HStack {
                                    Text(agent.agentId)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if agentId == agent.agentId && customAgentId.isEmpty {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.openClawRed)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    } header: {
                        Text("Agent")
                    }
                }

                Section {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading agents…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Agent ID", text: $customAgentId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: customAgentId) {
                            if !customAgentId.isEmpty {
                                agentId = customAgentId
                            }
                        }

                    if let error = loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(agents.isEmpty ? "Agent" : "Or enter manually")
                } footer: {
                    Text("Enter an agent ID not shown above, or use \"main\" for the default agent.")
                }
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let channel = Channel(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            agentId: agentId.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        channelStore.add(channel)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                await loadAgents()
            }
        }
    }

    private func loadAgents() async {
        guard settings.isConfigured else {
            loadError = "Configure your gateway in Settings first."
            return
        }

        isLoading = true
        do {
            let data = try await client.invokeTool(
                tool: "agents_list",
                gatewayURL: settings.settings.gatewayURL,
                token: settings.gatewayToken
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<AgentsListResult>.self, from: data)
            agents = wrapper.details?.agents ?? []
        } catch {
            loadError = "Could not load agents."
        }
        isLoading = false
    }
}
