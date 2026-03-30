import Foundation
import OSLog
import UIKit

/// Gateway WebSocket transport actor.
///
/// Handles connection lifecycle, v3 handshake with Ed25519 device identity,
/// RPC request/response with continuation-based waiting, server push events,
/// keepalive pings, tick monitoring, and automatic reconnection with backoff.
///
/// Ported from OpenClawKit's GatewayChannelActor, streamlined for ClawTalk.
actor GatewayWebSocket {

    // MARK: - Types

    /// Server-push messages from the gateway.
    enum Push: Sendable {
        case snapshot(HelloOk)
        case event(EventFrame)
        case seqGap(expected: Int, received: Int)
    }

    /// Connection state observable from outside the actor.
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
    }

    enum GatewayError: LocalizedError {
        case connectFailed(String)
        case requestTimeout(String)
        case responseError(method: String, code: String, message: String)
        case notConnected
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .connectFailed(let msg): return "Connect failed: \(msg)"
            case .requestTimeout(let method): return "\(method): request timed out"
            case .responseError(let method, let code, let msg): return "\(method): [\(code)] \(msg)"
            case .notConnected: return "Not connected to gateway"
            case .encodingFailed: return "Failed to encode request"
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "gateway-ws")
    private var wsTask: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<GatewayFrame, Error>] = [:]
    private var isConnected = false
    private var isConnecting = false
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    private var url: URL
    private var token: String?
    private var shouldReconnect = true
    private var backoffMs: Double = 500
    private var lastSeq: Int?
    private var lastTick: Date?
    private var tickIntervalMs: Double = 30000
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Timeouts
    private let connectTimeoutSeconds: Double = 12
    private let challengeTimeoutSeconds: Double = 6
    private let keepaliveIntervalSeconds: Double = 15
    private let defaultRequestTimeoutMs: Double = 15000

    // Background tasks
    private var watchdogTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?

    // Callbacks
    private let pushHandler: (@Sendable (Push) async -> Void)?
    private let stateHandler: (@Sendable (ConnectionState) async -> Void)?

    // Connect options
    private let role: String
    private let scopes: [String]
    private let caps: [String]
    private let commands: [String]
    private let clientMode: String

    // MARK: - Init

    init(
        url: URL,
        token: String?,
        role: String = "operator",
        scopes: [String] = ["operator.admin", "operator.read", "operator.write", "operator.approvals"],
        caps: [String] = [],
        commands: [String] = [],
        clientMode: String = "ui",
        pushHandler: (@Sendable (Push) async -> Void)? = nil,
        stateHandler: (@Sendable (ConnectionState) async -> Void)? = nil
    ) {
        self.url = url
        self.token = token
        self.role = role
        self.scopes = scopes
        self.caps = caps
        self.commands = commands
        self.clientMode = clientMode
        self.pushHandler = pushHandler
        self.stateHandler = stateHandler

        Task { [weak self] in
            await self?.startWatchdog()
        }
    }

    // MARK: - Public API

    /// Connect to the gateway. Safe to call multiple times — coalesces concurrent calls.
    func connect() async throws {
        if isConnected, wsTask?.state == .running { return }

        if isConnecting {
            try await withCheckedThrowingContinuation { cont in
                connectWaiters.append(cont)
            }
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        wsTask?.cancel(with: .goingAway, reason: nil)
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024 // 16 MB
        wsTask = task
        task.resume()

        await stateHandler?(.connecting)

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.performHandshake() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.connectTimeoutSeconds * 1_000_000_000))
                    // Cancel the WebSocket task to unblock any pending receive() calls,
                    // otherwise the task group hangs waiting for the cancelled child to finish.
                    await self.cancelWebSocketTask()
                    throw GatewayError.connectFailed("connect timed out")
                }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
            isConnected = false
            wsTask?.cancel(with: .goingAway, reason: nil)
            await stateHandler?(.disconnected)
            let waiters = connectWaiters
            connectWaiters.removeAll()
            for w in waiters { w.resume(throwing: error) }
            logger.error("gateway connect failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        listen()
        isConnected = true
        backoffMs = 500
        lastSeq = nil
        startKeepalive()
        await stateHandler?(.connected)

        let waiters = connectWaiters
        connectWaiters.removeAll()
        for w in waiters { w.resume(returning: ()) }
    }

    /// Shut down the connection. Does not auto-reconnect.
    func shutdown() async {
        shouldReconnect = false
        isConnected = false
        watchdogTask?.cancel(); watchdogTask = nil
        tickTask?.cancel(); tickTask = nil
        keepaliveTask?.cancel(); keepaliveTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil); wsTask = nil
        await stateHandler?(.disconnected)

        let error = GatewayError.notConnected
        let waiters = pending
        pending.removeAll()
        for (_, cont) in waiters { cont.resume(throwing: error) }

        let cWaiters = connectWaiters
        connectWaiters.removeAll()
        for w in cWaiters { w.resume(throwing: error) }
    }

    /// Send an RPC request and wait for the response.
    func request(method: String, params: [String: AnyCodable]? = nil, timeoutMs: Double? = nil) async throws -> Data {
        try await ensureConnected()
        let timeout = timeoutMs ?? defaultRequestTimeoutMs

        let id = UUID().uuidString
        let frame = RequestFrame(method: method, id: id, params: params.map { AnyCodable($0) })
        let data = try encoder.encode(frame)

        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GatewayFrame, Error>) in
            pending[id] = cont

            // Timeout task
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000))
                await self?.timeoutRequest(id: id)
            }

            // Send task
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.wsTask?.send(.data(data))
                } catch {
                    let cont = await self.removePending(id: id)
                    await self.handleSendFailure(error)
                    cont?.resume(throwing: error)
                }
            }
        }

        guard case let .res(res) = response else {
            throw GatewayError.responseError(method: method, code: "UNEXPECTED", message: "unexpected frame type")
        }

        if !res.ok {
            let code = res.error?["code"]?.value as? String ?? "GATEWAY_ERROR"
            let msg = res.error?["message"]?.value as? String ?? "gateway error"
            throw GatewayError.responseError(method: method, code: code, message: msg)
        }

        if let payload = res.payload {
            return try encoder.encode(payload)
        }
        return Data()
    }

    /// Send a fire-and-forget message (no response expected).
    func send(method: String, params: [String: AnyCodable]? = nil) async throws {
        try await ensureConnected()
        let id = UUID().uuidString
        let frame = RequestFrame(method: method, id: id, params: params.map { AnyCodable($0) })
        let data = try encoder.encode(frame)

        do {
            try await wsTask?.send(.data(data))
        } catch {
            await handleSendFailure(error)
            throw error
        }
    }

    /// Decode a typed response from an RPC call.
    func requestDecoded<T: Decodable>(method: String, params: [String: AnyCodable]? = nil, timeoutMs: Double? = nil) async throws -> T {
        let data = try await request(method: method, params: params, timeoutMs: timeoutMs)
        return try decoder.decode(T.self, from: data)
    }

    /// Update connection URL and token (for settings changes).
    func updateConnection(url: URL, token: String?) {
        self.url = url
        self.token = token
    }

    var connectionState: ConnectionState {
        if isConnected { return .connected }
        if isConnecting { return .connecting }
        return .disconnected
    }

    // MARK: - Handshake

    private func performHandshake() async throws {
        // Step 1: Wait for connect.challenge
        let nonce = try await waitForChallenge()

        // Step 2: Build and send connect request
        let identity = DeviceIdentityManager.loadOrCreate()
        let gatewayHost = url.host ?? ""
        let storedToken = DeviceAuthTokenStore.loadToken(deviceId: identity.deviceId, role: role, gatewayHost: gatewayHost)?.token
        let authToken = storedToken ?? token

        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let platform = "ios"
        let deviceFamily = await UIDevice.current.model.lowercased()

        // Use v2 payload format (compatible with all gateway versions).
        // v3 adds platform/deviceFamily but requires newer gateway builds.
        let authPayload = GatewayDeviceAuthPayload.buildV2(
            deviceId: identity.deviceId,
            clientId: "openclaw-ios",
            clientMode: clientMode,
            role: role,
            scopes: scopes,
            signedAtMs: signedAtMs,
            token: authToken,
            nonce: nonce
        )

        logger.debug("handshake: v2 payload built, deviceId=\(identity.deviceId.prefix(8), privacy: .public)…")

        var params: [String: AnyCodable] = [
            "minProtocol": AnyCodable(GATEWAY_PROTOCOL_VERSION),
            "maxProtocol": AnyCodable(GATEWAY_PROTOCOL_VERSION),
            "client": AnyCodable([
                "id": AnyCodable("openclaw-ios"),
                "displayName": AnyCodable("ClawTalk"),
                "version": AnyCodable(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"),
                "platform": AnyCodable(platform),
                "mode": AnyCodable(clientMode),
                "deviceFamily": AnyCodable(deviceFamily),
            ] as [String: AnyCodable]),
            "caps": AnyCodable(caps.map { AnyCodable($0) }),
            "commands": AnyCodable(commands.map { AnyCodable($0) }),
            "locale": AnyCodable(Locale.preferredLanguages.first ?? Locale.current.identifier),
            "userAgent": AnyCodable(ProcessInfo.processInfo.operatingSystemVersionString),
            "role": AnyCodable(role),
            "scopes": AnyCodable(scopes.map { AnyCodable($0) }),
        ]

        if let authToken {
            params["auth"] = AnyCodable(["token": AnyCodable(authToken)] as [String: AnyCodable])
        }

        if let device = GatewayDeviceAuthPayload.signedDeviceDictionary(
            payload: authPayload,
            identity: identity,
            signedAtMs: signedAtMs,
            nonce: nonce
        ) {
            params["device"] = AnyCodable(device)
        } else {
            logger.error("failed to build signed device dictionary")
        }

        let reqId = UUID().uuidString
        let frame = RequestFrame(method: "connect", id: reqId, params: AnyCodable(params))
        let data = try encoder.encode(frame)
        try await wsTask?.send(.data(data))

        // Step 3: Wait for connect response
        let response = try await waitForConnectResponse(reqId: reqId)
        try await handleConnectResponse(response, identity: identity)
    }

    private func waitForChallenge() async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw GatewayError.connectFailed("deallocated") }
                while true {
                    guard let task = await self.wsTask else { throw GatewayError.connectFailed("no socket") }
                    let msg = try await task.receive()
                    guard let data = self.decodeMessageData(msg),
                          let frame = try? self.decoder.decode(GatewayFrame.self, from: data),
                          case let .event(evt) = frame,
                          evt.event == "connect.challenge",
                          let payload = evt.payload?.dictValue,
                          let nonce = payload["nonce"]?.stringValue,
                          !nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { continue }
                    return nonce
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.challengeTimeoutSeconds * 1_000_000_000))
                await self.cancelWebSocketTask()
                throw GatewayError.connectFailed("challenge timeout")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func waitForConnectResponse(reqId: String) async throws -> ResponseFrame {
        guard let task = wsTask else {
            throw GatewayError.connectFailed("no socket")
        }
        while true {
            let msg = try await task.receive()
            guard let data = decodeMessageData(msg),
                  let frame = try? decoder.decode(GatewayFrame.self, from: data),
                  case let .res(res) = frame,
                  res.id == reqId
            else { continue }
            return res
        }
    }

    private func handleConnectResponse(_ res: ResponseFrame, identity: DeviceIdentity) async throws {
        guard res.ok else {
            let msg = res.error?["message"]?.value as? String ?? "gateway connect rejected"
            throw GatewayError.connectFailed(msg)
        }

        guard let payload = res.payload else {
            throw GatewayError.connectFailed("missing payload")
        }

        let payloadData = try encoder.encode(payload)
        let ok = try decoder.decode(HelloOk.self, from: payloadData)

        // Extract tick interval
        if let tick = ok.policy["tickIntervalMs"]?.value as? Double {
            tickIntervalMs = tick
        } else if let tick = ok.policy["tickIntervalMs"]?.value as? Int {
            tickIntervalMs = Double(tick)
        }

        // Store device token if returned
        if let auth = ok.auth,
           let deviceToken = auth["deviceToken"]?.stringValue {
            let authRole = auth["role"]?.stringValue ?? role
            let scopeValues = auth["scopes"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            let gatewayHost = url.host ?? ""
            DeviceAuthTokenStore.storeToken(
                deviceId: identity.deviceId,
                role: authRole,
                gatewayHost: gatewayHost,
                token: deviceToken,
                scopes: scopeValues
            )
        }

        lastTick = Date()
        startTickWatcher()
        await pushHandler?(.snapshot(ok))

        logger.info("gateway connected (protocol \(ok._protocol))")
    }

    // MARK: - Message Loop

    private func listen() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                Task { await self.handleReceiveFailure(err) }
            case .success(let msg):
                Task {
                    await self.handleMessage(msg)
                    await self.listen()
                }
            }
        }
    }

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) async {
        guard let data = decodeMessageData(msg),
              let frame = try? decoder.decode(GatewayFrame.self, from: data)
        else { return }

        switch frame {
        case .res(let res):
            if let cont = pending.removeValue(forKey: res.id) {
                cont.resume(returning: .res(res))
            }
        case .event(let evt):
            if evt.event == "connect.challenge" { return }
            if let seq = evt.seq {
                if let last = lastSeq, seq > last + 1 {
                    await pushHandler?(.seqGap(expected: last + 1, received: seq))
                }
                lastSeq = seq
            }
            if evt.event == "tick" { lastTick = Date() }
            await pushHandler?(.event(evt))
        default:
            break
        }
    }

    private func handleReceiveFailure(_ err: Error) async {
        logger.error("gateway receive failed: \(err.localizedDescription, privacy: .public)")
        isConnected = false
        keepaliveTask?.cancel(); keepaliveTask = nil
        await stateHandler?(.disconnected)
        failAllPending(err)
        await scheduleReconnect()
    }

    private nonisolated func decodeMessageData(_ msg: URLSessionWebSocketTask.Message) -> Data? {
        switch msg {
        case .data(let d): return d
        case .string(let s): return s.data(using: .utf8)
        @unknown default: return nil
        }
    }

    // MARK: - Keepalive & Tick Watcher

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            guard let self else { return }
            while await self.shouldReconnect {
                guard await self.sleepUnlessCancelled(seconds: self.keepaliveIntervalSeconds) else { return }
                guard await self.isConnected, let task = await self.wsTask else { continue }
                try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    task.sendPing { error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: ()) }
                    }
                }
            }
        }
    }

    private func startTickWatcher() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            guard let self else { return }
            let tolerance = await self.tickIntervalMs * 2
            while await self.isConnected {
                guard await self.sleepUnlessCancelled(seconds: tolerance / 1000) else { return }
                guard await self.isConnected else { return }
                if let last = await self.lastTick {
                    let delta = Date().timeIntervalSince(last) * 1000
                    if delta > tolerance {
                        self.logger.error("gateway tick missed; reconnecting")
                        await self.markDisconnected()
                        await self.scheduleReconnect()
                        return
                    }
                }
            }
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            guard let self else { return }
            while await self.shouldReconnect {
                guard await self.sleepUnlessCancelled(seconds: 30) else { return }
                guard await self.shouldReconnect else { return }
                if await self.isConnected { continue }
                do {
                    try await self.connect()
                } catch {
                    self.logger.error("watchdog reconnect failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() async {
        guard shouldReconnect else { return }
        let delay = backoffMs / 1000
        backoffMs = min(backoffMs * 2, 30000)
        guard await sleepUnlessCancelled(seconds: delay) else { return }
        guard shouldReconnect else { return }
        do {
            try await connect()
        } catch {
            logger.error("reconnect failed: \(error.localizedDescription, privacy: .public)")
            await scheduleReconnect()
        }
    }

    private func markDisconnected() {
        isConnected = false
        keepaliveTask?.cancel(); keepaliveTask = nil
        failAllPending(GatewayError.notConnected)
        Task { await stateHandler?(.disconnected) }
    }

    // MARK: - Helpers

    /// Cancel the current WebSocket task. Used by timeout handlers to unblock pending receive() calls.
    private func cancelWebSocketTask() {
        wsTask?.cancel(with: .goingAway, reason: nil)
    }

    private func ensureConnected() async throws {
        try await connect()
    }

    private func removePending(id: String) -> CheckedContinuation<GatewayFrame, Error>? {
        pending.removeValue(forKey: id)
    }

    private func handleSendFailure(_ error: Error) async {
        isConnected = false
        wsTask?.cancel(with: .goingAway, reason: nil)
        await stateHandler?(.disconnected)
        await scheduleReconnect()
    }

    private func failAllPending(_ error: Error) {
        let waiters = pending
        pending.removeAll()
        for (_, cont) in waiters {
            cont.resume(throwing: error)
        }
    }

    private func timeoutRequest(id: String) {
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(throwing: GatewayError.requestTimeout(id))
    }

    private nonisolated func sleepUnlessCancelled(seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}
