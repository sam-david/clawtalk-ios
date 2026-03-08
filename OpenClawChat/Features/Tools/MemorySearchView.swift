import SwiftUI

struct MemorySearchView: View {
    @Bindable var viewModel: ToolsViewModel

    var body: some View {
        List {
            if viewModel.memoryResults.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Search Memory",
                    systemImage: "brain.head.profile",
                    description: Text("Search your agent's memory for stored knowledge.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(viewModel.memoryResults) { entry in
                NavigationLink {
                    MemoryDetailView(viewModel: viewModel, path: entry.path)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.path)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.openClawRed)

                            Spacer()

                            Text(String(format: "%.0f%%", entry.score * 100))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.systemGray5)))
                        }

                        Text(entry.snippet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        if let source = entry.source {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Memory")
        .searchable(text: $viewModel.memorySearchQuery, prompt: "Search agent memory...")
        .onSubmit(of: .search) {
            Task { await viewModel.searchMemory() }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
            Text(message)
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
