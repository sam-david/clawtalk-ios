import SwiftUI

struct ModelsView: View {
    @Bindable var viewModel: ToolsViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingModels {
                ProgressView("Loading models...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadModels() }
                    }
                }
            } else if viewModel.availableModels.isEmpty {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "sparkles",
                    description: Text("No models returned from the gateway.")
                )
            } else {
                modelsList
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.availableModels.isEmpty {
                await viewModel.loadModels()
            }
        }
    }

    private var modelsList: some View {
        List {
            ForEach(groupedProviders, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.models) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.body)
                                .fontWeight(.medium)

                            HStack(spacing: 12) {
                                if let ctx = model.contextWindow {
                                    Label(formatTokenCount(ctx), systemImage: "text.word.spacing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if model.reasoning == true {
                                    Label("Reasoning", systemImage: "brain")
                                        .font(.caption)
                                        .foregroundStyle(.openClawRed)
                                }
                            }

                            Text(model.id)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private struct ProviderGroup {
        let provider: String
        let models: [ModelEntry]
    }

    private var groupedProviders: [ProviderGroup] {
        let grouped = Dictionary(grouping: viewModel.availableModels) { $0.provider ?? "Other" }
        return grouped.keys.sorted().map { ProviderGroup(provider: $0, models: grouped[$0]!) }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000)k context"
        } else if count >= 1_000 {
            return "\(count / 1_000)k context"
        }
        return "\(count) context"
    }
}
