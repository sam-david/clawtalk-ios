import Foundation

final class ConversationStore {
    static let shared = ConversationStore()

    private let baseDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("conversations")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Legacy single-file path (migrated on first per-channel load).
    private let legacyFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("conversations.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func fileURL(for channelId: UUID) -> URL {
        baseDir.appendingPathComponent("\(channelId.uuidString).json")
    }

    func load(channelId: UUID) -> [Message] {
        let url = fileURL(for: channelId)

        // Migrate legacy conversations to default channel on first load
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try? FileManager.default.moveItem(at: legacyFileURL, to: url)
        }

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let messages = try? decoder.decode([Message].self, from: data) else {
            return []
        }
        return messages.map { msg in
            var m = msg
            m.isStreaming = false
            return m
        }
    }

    func save(_ messages: [Message], channelId: UUID) {
        let completed = messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        guard let data = try? encoder.encode(completed) else { return }
        try? data.write(to: fileURL(for: channelId), options: [.atomic, .completeFileProtection])
    }

    func clear(channelId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: channelId))
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: baseDir)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: legacyFileURL)
    }
}
