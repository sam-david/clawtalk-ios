import SwiftUI

struct FileReadView: View {
    @Bindable var viewModel: ToolsViewModel
    @State private var pathInput = ""

    var body: some View {
        VStack(spacing: 0) {
            // Path input bar
            HStack(spacing: 10) {
                TextField("File path...", text: $pathInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        readCurrentPath()
                    }

                Button(action: readCurrentPath) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.openClawRed)
                }
                .disabled(pathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding()

            Divider()

            // Content area
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let content = viewModel.fileContent {
                ScrollView {
                    Text(content)
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
            } else {
                ContentUnavailableView(
                    "Read a File",
                    systemImage: "doc.text",
                    description: Text("Enter a file path from your agent's workspace to view its contents.")
                )
            }
        }
        .navigationTitle("Files")
    }

    private func readCurrentPath() {
        let path = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        Task { await viewModel.readFile(path: path) }
    }
}
