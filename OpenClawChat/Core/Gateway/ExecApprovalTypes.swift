import Foundation

// MARK: - Exec Approval Request (from push event)

struct ExecApprovalEvent: Decodable, Sendable {
    let id: String
    let request: ExecApprovalRequest
    let createdAtMs: Double
    let expiresAtMs: Double
}

struct ExecApprovalRequest: Decodable, Sendable {
    let command: String
    let commandArgv: [String]?
    let cwd: String?
    let host: String?
    let security: String?
    let ask: String?
    let agentId: String?
    let sessionKey: String?
}

// MARK: - Exec Approval Resolved (from push event)

struct ExecApprovalResolvedEvent: Decodable, Sendable {
    let id: String
    let decision: String
    let resolvedBy: String?
    let ts: Double?
}

// MARK: - Pending Approval (client-side tracking)

struct PendingApproval: Identifiable, Sendable {
    let id: String
    let command: String
    let commandArgv: [String]?
    let cwd: String?
    let host: String?
    let agentId: String?
    let ask: String?
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    var displayCommand: String {
        if let argv = commandArgv, !argv.isEmpty {
            return argv.joined(separator: " ")
        }
        return command
    }
}
