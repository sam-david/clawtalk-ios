import SwiftUI

struct AgentsView: View {
    @Bindable var viewModel: ToolsViewModel

    var body: some View {
        List {
            if viewModel.isLoading && viewModel.agents.isEmpty {
                ProgressView("Loading agents...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if viewModel.agents.isEmpty {
                Text("No agents found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.agents) { agent in
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(Color.openClawRed)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.agentId)
                                .font(.headline)
                        }

                        Spacer()

                        if agent.configured == true {
                            Text("configured")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        } else {
                            Text("default")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Agents")
        .refreshable {
            await viewModel.listAgents()
        }
        .task {
            await viewModel.listAgents()
        }
    }
}
