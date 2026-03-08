import SwiftUI
import MarkdownUI

struct MemoryDetailView: View {
    @Bindable var viewModel: ToolsViewModel
    let path: String

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let result = viewModel.memoryFileContent {
                if let error = result.error {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if path.hasSuffix(".md") {
                    Markdown(result.text)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)
                        .padding()
                } else {
                    Text(result.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            }
        }
        .navigationTitle(path)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.getMemoryFile(path: path)
        }
    }
}
