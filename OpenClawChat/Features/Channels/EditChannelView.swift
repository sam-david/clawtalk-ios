import SwiftUI

struct EditChannelView: View {
    @Environment(\.dismiss) private var dismiss
    var channelStore: ChannelStore
    var channel: Channel

    @State private var name: String
    @State private var agentId: String

    init(channelStore: ChannelStore, channel: Channel) {
        self.channelStore = channelStore
        self.channel = channel
        _name = State(initialValue: channel.name)
        _agentId = State(initialValue: channel.agentId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel Name") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Agent ID") {
                    TextField("Agent ID", text: $agentId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Edit Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = channel
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !updated.name.isEmpty && !updated.agentId.isEmpty {
                            channelStore.update(updated)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
