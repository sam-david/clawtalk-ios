import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var imageData: [Data]?
    var tokenUsage: TokenUsage?
    var responseId: String?
    var modelName: String?
    var sendError: String?

    init(role: MessageRole, content: String, isStreaming: Bool = false, imageData: [Data]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.imageData = imageData
    }

    var hasImages: Bool {
        guard let images = imageData else { return false }
        return !images.isEmpty
    }

    var hasFailed: Bool {
        sendError != nil
    }
}
