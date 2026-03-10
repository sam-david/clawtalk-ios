import SwiftUI

struct ChannelListView: View {
    @Bindable var channelStore: ChannelStore
    var settingsStore: SettingsStore
    var gatewayConnection: GatewayConnection
    var onSelect: (Channel) -> Void

    @State private var showAddChannel = false
    @State private var showSettings = false
    @State private var showTools = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(channelStore.channels) { channel in
                    Button(action: { onSelect(channel) }) {
                        HStack(spacing: 12) {
                            Text(channel.name.prefix(1).uppercased())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.openClawRed)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text("openclaw:\(channel.agentId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        channelStore.delete(channelStore.channels[idx])
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.subheadline)
                            .foregroundStyle(.openClawRed)
                        Text("ClawTalk")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.openClawRed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showTools = true }) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(.openClawRed)
                        }
                        Button(action: { showAddChannel = true }) {
                            Image(systemName: "plus")
                                .foregroundStyle(.openClawRed)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: settingsStore, gatewayConnection: gatewayConnection)
            }
            .sheet(isPresented: $showAddChannel) {
                AddChannelView(channelStore: channelStore, settings: settingsStore)
            }
            .sheet(isPresented: $showTools) {
                ToolsView(settings: settingsStore)
            }
        }
    }
}
