import Foundation
import OSLog
import UIKit

/// High-level gateway connection wrapper over GatewayWebSocket.
/// Provides chat-specific methods and event routing.
@Observable
@MainActor
final class GatewayConnection {

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
    }

    // MARK: - Observable State

    private(set) var connectionState: State = .disconnected
    private(set) var lastError: String?
    private(set) var pendingApprovals: [PendingApproval] = []
    private(set) var agentStatus: AgentStatusInfo?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "gateway-conn")
    private var gateway: GatewayWebSocket?
    private var eventContinuations: [UUID: AsyncStream<ChatEventPayload>.Continuation] = [:]

    // MARK: - Connection Lifecycle

    /// Connect to the gateway WebSocket.
    /// - Parameter resolvedURL: Full WebSocket URL (e.g. wss://host/ws or ws://host:18789).
    func connect(resolvedURL: String, token: String) async {
        guard let wsURL = URL(string: resolvedURL) else {
            lastError = "Invalid WebSocket URL: \(resolvedURL)"
            return
        }

        // Shut down existing connection if any
        if let existing = gateway {
            await existing.shutdown()
        }

        connectionState = .connecting
        lastError = nil
        logger.info("gateway connecting to \(wsURL.absoluteString, privacy: .public)")

        let gw = GatewayWebSocket(
            url: wsURL,
            token: token,
            pushHandler: { [weak self] push in
                await self?.handlePush(push)
            },
            stateHandler: { [weak self] state in
                await self?.handleStateChange(state)
            }
        )
        gateway = gw

        do {
            try await gw.connect()
            logger.info("gateway connect succeeded, setting state to .connected")
            connectionState = .connected
        } catch {
            logger.error("gateway connect failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .disconnected
            lastError = error.localizedDescription
        }
    }

    /// Disconnect from the gateway.
    func disconnect() async {
        if let gw = gateway {
            await gw.shutdown()
        }
        gateway = nil
        connectionState = .disconnected
    }

    // MARK: - Chat

    /// Send a chat message via WebSocket. Returns the runId for tracking events.
    /// - Parameter images: Optional array of JPEG image data sent as base64 attachments.
    func chatSend(
        sessionKey: String,
        message: String,
        images: [Data]? = nil,
        idempotencyKey: String = UUID().uuidString,
        timeoutMs: Int = 30000
    ) async throws -> ChatSendResponse {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        var params: [String: AnyCodable] = [
            "sessionKey": AnyCodable(sessionKey),
            "message": AnyCodable(message),
            "thinking": AnyCodable(""),
            "idempotencyKey": AnyCodable(idempotencyKey),
            "timeoutMs": AnyCodable(timeoutMs),
        ]

        if let images, !images.isEmpty {
            let attachments: [[String: AnyCodable]] = images.map { data in
                [
                    "type": AnyCodable("image"),
                    "mimeType": AnyCodable("image/jpeg"),
                    "content": AnyCodable(data.base64EncodedString()),
                ]
            }
            params["attachments"] = AnyCodable(attachments.map { AnyCodable($0) })
        }

        return try await gw.requestDecoded(
            method: "chat.send",
            params: params,
            timeoutMs: Double(timeoutMs)
        )
    }

    /// Fetch chat history from the server.
    func chatHistory(sessionKey: String, limit: Int? = nil) async throws -> ChatHistoryPayload {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        var params: [String: AnyCodable] = ["sessionKey": AnyCodable(sessionKey)]
        if let limit { params["limit"] = AnyCodable(limit) }

        return try await gw.requestDecoded(method: "chat.history", params: params)
    }

    /// Abort an in-progress chat run.
    func chatAbort(sessionKey: String, runId: String) async throws -> Bool {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }

        struct AbortResponse: Decodable { let ok: Bool?; let aborted: Bool? }
        let res: AbortResponse = try await gw.requestDecoded(
            method: "chat.abort",
            params: [
                "sessionKey": AnyCodable(sessionKey),
                "runId": AnyCodable(runId),
            ]
        )
        return res.aborted ?? false
    }

    /// Subscribe to chat events. Returns an AsyncStream that yields ChatEventPayload.
    /// Call this BEFORE chatSend to ensure no events are missed.
    func subscribeChatEvents() -> (id: UUID, stream: AsyncStream<ChatEventPayload>) {
        let id = UUID()
        let stream = AsyncStream<ChatEventPayload> { continuation in
            self.eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.eventContinuations.removeValue(forKey: id)
                }
            }
        }
        return (id, stream)
    }

    /// Unsubscribe from chat events.
    func unsubscribeChatEvents(id: UUID) {
        eventContinuations[id]?.finish()
        eventContinuations.removeValue(forKey: id)
    }

    // MARK: - Models

    /// Fetch available models via WebSocket RPC.
    func modelsList() async throws -> [ModelEntry] {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }
        let response: ModelsListResponse = try await gw.requestDecoded(method: "models.list")
        return response.models
    }

    // MARK: - Exec Approvals

    /// Resolve a pending exec approval.
    func resolveApproval(id: String, decision: String) async throws {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }
        let _: ApprovalResolveResponse = try await gw.requestDecoded(
            method: "exec.approval.resolve",
            params: [
                "id": AnyCodable(id),
                "decision": AnyCodable(decision),
            ]
        )
        // Remove from pending list immediately
        pendingApprovals.removeAll { $0.id == id }
        logger.info("approval resolved: \(id, privacy: .public) → \(decision, privacy: .public)")
    }

    /// Remove expired approvals.
    func pruneExpiredApprovals() {
        pendingApprovals.removeAll { $0.isExpired }
    }

    // MARK: - RPC Convenience

    /// Make a raw RPC request.
    func request(method: String, params: [String: AnyCodable]? = nil) async throws -> Data {
        guard let gw = gateway else { throw GatewayWebSocket.GatewayError.notConnected }
        return try await gw.request(method: method, params: params)
    }

    // MARK: - Event Handling

    private func handlePush(_ push: GatewayWebSocket.Push) async {
        switch push {
        case .snapshot(let hello):
            logger.info("gateway snapshot received (uptime: \(hello.snapshot.uptimems)ms)")
        case .event(let evt):
            switch evt.event {
            case "chat":
                decodeChatEvent(evt)
            case "exec.approval.requested":
                handleApprovalRequested(evt)
            case "exec.approval.resolved":
                handleApprovalResolved(evt)
            case "agent":
                handleAgentEvent(evt)
            default:
                break
            }
        case .seqGap(let expected, let received):
            logger.warning("event sequence gap: expected \(expected), got \(received)")
        }
    }

    private func decodeChatEvent(_ evt: EventFrame) {
        guard let payload = evt.payload else { return }

        // Encode AnyCodable back to JSON, then decode to typed struct
        guard let data = try? JSONEncoder().encode(payload),
              let chatEvent = try? JSONDecoder().decode(ChatEventPayload.self, from: data)
        else { return }

        for (_, continuation) in eventContinuations {
            continuation.yield(chatEvent)
        }
    }

    private func handleApprovalRequested(_ evt: EventFrame) {
        guard let payload = evt.payload,
              let data = try? JSONEncoder().encode(payload),
              let event = try? JSONDecoder().decode(ExecApprovalEvent.self, from: data)
        else {
            logger.error("failed to decode exec.approval.requested")
            return
        }

        let approval = PendingApproval(
            id: event.id,
            command: event.request.command,
            commandArgv: event.request.commandArgv,
            cwd: event.request.cwd,
            host: event.request.host,
            agentId: event.request.agentId,
            ask: event.request.ask,
            createdAt: Date(timeIntervalSince1970: event.createdAtMs / 1000),
            expiresAt: Date(timeIntervalSince1970: event.expiresAtMs / 1000)
        )

        // Don't add duplicates
        if !pendingApprovals.contains(where: { $0.id == approval.id }) {
            pendingApprovals.append(approval)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            logger.info("approval requested: \(approval.displayCommand, privacy: .public)")
        }
    }

    private func handleApprovalResolved(_ evt: EventFrame) {
        guard let payload = evt.payload,
              let data = try? JSONEncoder().encode(payload),
              let event = try? JSONDecoder().decode(ExecApprovalResolvedEvent.self, from: data)
        else { return }

        pendingApprovals.removeAll { $0.id == event.id }
        logger.info("approval resolved externally: \(event.id, privacy: .public) → \(event.decision, privacy: .public)")
    }

    private func handleAgentEvent(_ evt: EventFrame) {
        guard let payload = evt.payload,
              let data = try? JSONEncoder().encode(payload),
              let status = try? JSONDecoder().decode(AgentStatusInfo.self, from: data)
        else { return }

        agentStatus = status
        logger.info("agent status: \(status.status ?? "unknown", privacy: .public)")
    }

    private func handleStateChange(_ state: GatewayWebSocket.ConnectionState) {
        let newState: State = switch state {
        case .connected: .connected
        case .connecting: .connecting
        case .disconnected: .disconnected
        }
        logger.info("gateway state: \(String(describing: self.connectionState)) → \(String(describing: newState))")
        connectionState = newState

        if newState == .disconnected {
            pendingApprovals.removeAll()
            agentStatus = nil
        }
    }

}

// MARK: - Chat Event Types

struct ChatSendResponse: Codable, Sendable {
    let runId: String
    let status: String
}

struct ChatEventPayload: Codable, Sendable {
    let runId: String?
    let sessionKey: String?
    let state: String?     // "delta", "final", "error"
    let message: ChatEventMessage?
    let errorMessage: String?
    let stopReason: String?
}

struct ChatEventMessage: Codable, Sendable {
    let role: String?
    let content: [ChatEventContent]?
    let timestamp: Int?
}

struct ChatEventContent: Codable, Sendable {
    let type: String?
    let text: String?
}

struct ChatHistoryPayload: Codable, Sendable {
    let sessionKey: String?
    let sessionId: String?
    let messages: [ChatHistoryMessage]?
    let thinkingLevel: String?
}

struct ChatHistoryMessage: Codable, Sendable {
    let role: String?
    let content: AnyCodable?  // Can be string or array of content parts
    let timestamp: Int?
}

// MARK: - Approval Response

struct ApprovalResolveResponse: Decodable {
    let ok: Bool?
}

// MARK: - Agent Status

struct AgentStatusInfo: Decodable, Sendable {
    let status: String?
    let agentId: String?
    let sessionKey: String?
    let message: String?
}
