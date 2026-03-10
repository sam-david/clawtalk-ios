import Foundation
import OSLog
import UIKit
import UserNotifications

/// Manages a WebSocket connection with role "node", allowing the agent
/// to invoke device capabilities (device info, notifications, etc.).
@Observable
@MainActor
final class NodeConnection {

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var connectionState: State = .disconnected
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "node-conn")
    private var gateway: GatewayWebSocket?

    // MARK: - Capabilities

    private static let declaredCaps = [
        "device", "notifications", "location", "contacts",
        "calendar", "reminders", "motion", "photos", "camera",
        "screen", "canvas", "voice",
    ]
    private static let declaredCommands = [
        "device.status", "device.info",
        "system.notify",
        "location.get",
        "contacts.search", "contacts.add",
        "calendar.events", "calendar.add",
        "reminders.list", "reminders.add",
        "motion.activity", "motion.pedometer",
        "photos.latest",
        "camera.list", "camera.snap",
        "screen.snapshot",
        "canvas.present", "canvas.navigate",
        "canvas.evalJS", "canvas.snapshot", "canvas.reset",
        "voicewake.set", "voicewake.get",
    ]

    // MARK: - Connect

    func connect(resolvedURL: String, token: String) async {
        guard let wsURL = URL(string: resolvedURL) else {
            lastError = "Invalid WebSocket URL"
            return
        }

        if let existing = gateway {
            await existing.shutdown()
        }

        connectionState = .connecting
        lastError = nil
        logger.info("node connecting to \(wsURL.absoluteString, privacy: .public)")

        let gw = GatewayWebSocket(
            url: wsURL,
            token: token,
            role: "node",
            scopes: [],
            caps: Self.declaredCaps,
            commands: Self.declaredCommands,
            clientMode: "node",
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
            connectionState = .connected
            logger.info("node connected")
        } catch {
            logger.error("node connect failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .disconnected
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        if let gw = gateway {
            await gw.shutdown()
        }
        gateway = nil
        connectionState = .disconnected
    }

    // MARK: - Event Handling

    private func handlePush(_ push: GatewayWebSocket.Push) async {
        switch push {
        case .snapshot:
            logger.info("node snapshot received")
        case .event(let evt):
            if evt.event == "node.invoke.request" {
                await handleInvokeRequest(evt)
            }
        case .seqGap(let expected, let received):
            logger.warning("node event sequence gap: expected \(expected), got \(received)")
        }
    }

    private func handleStateChange(_ state: GatewayWebSocket.ConnectionState) {
        let newState: State = switch state {
        case .connected: .connected
        case .connecting: .connecting
        case .disconnected: .disconnected
        }
        connectionState = newState
    }

    // MARK: - Invoke Dispatch

    private func handleInvokeRequest(_ evt: EventFrame) async {
        guard let payload = evt.payload,
              let data = try? JSONEncoder().encode(payload),
              let request = try? JSONDecoder().decode(NodeInvokeRequest.self, from: data)
        else {
            logger.error("failed to decode node.invoke.request")
            return
        }

        logger.info("node.invoke: \(request.command, privacy: .public)")

        let result: NodeInvokeResult
        do {
            let response = try await dispatchCommand(request)
            result = NodeInvokeResult(
                id: request.id,
                nodeId: request.nodeId,
                ok: true,
                payloadJSON: response,
                error: nil
            )
        } catch {
            result = NodeInvokeResult(
                id: request.id,
                nodeId: request.nodeId,
                ok: false,
                payloadJSON: nil,
                error: NodeInvokeError(code: "UNAVAILABLE", message: error.localizedDescription)
            )
        }

        // Send result back to gateway
        do {
            guard let gw = gateway else { return }
            let resultData = try JSONEncoder().encode(result)
            let resultCodable = try JSONDecoder().decode(AnyCodable.self, from: resultData)
            let paramsDict = resultCodable.dictValue ?? [:]
            _ = try await gw.request(method: "node.invoke.result", params: paramsDict)
        } catch {
            logger.error("failed to send invoke result: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func dispatchCommand(_ request: NodeInvokeRequest) async throws -> String? {
        switch request.command {
        // Device
        case "device.info":
            return try encodeJSON(DeviceInfoCapability.getInfo())
        case "device.status":
            return try await encodeJSON(DeviceInfoCapability.getStatus())

        // Notifications
        case "system.notify":
            let params = request.decodedParams(as: SystemNotifyParams.self)
            try await NotificationCapability.notify(
                title: params?.title,
                body: params?.body,
                sound: params?.sound,
                priority: params?.priority
            )
            return "{\"ok\":true}"

        // Location
        case "location.get":
            return try await encodeJSON(LocationCapability.getLocation())

        // Contacts
        case "contacts.search":
            let params = request.decodedParams(as: ContactsSearchParams.self)
            let results = try await ContactsCapability.search(
                query: params?.query ?? "",
                limit: params?.limit ?? 20
            )
            return try encodeJSON(results)
        case "contacts.add":
            let params = request.decodedParams(as: ContactsAddParams.self)
            let result = try await ContactsCapability.addContact(
                givenName: params?.givenName,
                familyName: params?.familyName,
                phoneNumber: params?.phoneNumber,
                email: params?.email,
                organization: params?.organization
            )
            return try encodeJSON(result)

        // Calendar
        case "calendar.events":
            let params = request.decodedParams(as: CalendarEventsParams.self)
            let events = try await CalendarCapability.listEvents(
                daysAhead: params?.daysAhead ?? 7,
                daysBack: params?.daysBack ?? 0
            )
            return try encodeJSON(events)
        case "calendar.add":
            guard let params = request.decodedParams(as: CalendarAddParams.self) else {
                throw NodeError.unavailable("Missing calendar event params")
            }
            let result = try await CalendarCapability.addEvent(
                title: params.title,
                startDate: params.startDate,
                endDate: params.endDate,
                location: params.location,
                notes: params.notes,
                isAllDay: params.isAllDay
            )
            return try encodeJSON(result)

        // Reminders
        case "reminders.list":
            let params = request.decodedParams(as: RemindersListParams.self)
            let reminders = try await CalendarCapability.listReminders(completed: params?.completed)
            return try encodeJSON(reminders)
        case "reminders.add":
            guard let params = request.decodedParams(as: RemindersAddParams.self) else {
                throw NodeError.unavailable("Missing reminder params")
            }
            let result = try await CalendarCapability.addReminder(
                title: params.title,
                dueDate: params.dueDate,
                notes: params.notes,
                priority: params.priority
            )
            return try encodeJSON(result)

        // Motion
        case "motion.activity":
            let params = request.decodedParams(as: MotionActivityParams.self)
            let activities = try await MotionCapability.getActivity(hours: params?.hours ?? 1)
            return try encodeJSON(activities)
        case "motion.pedometer":
            let params = request.decodedParams(as: MotionPedometerParams.self)
            let data = try await MotionCapability.getPedometer(hours: params?.hours ?? 24)
            return try encodeJSON(data)

        // Photos
        case "photos.latest":
            let params = request.decodedParams(as: PhotosLatestParams.self)
            let photos = try await PhotosCapability.getLatest(
                count: params?.count ?? 5,
                includeImage: params?.includeImage ?? true,
                maxWidth: params?.maxWidth ?? 1024
            )
            return try encodeJSON(photos)

        // Camera
        case "camera.list":
            return try encodeJSON(CameraCapability.listCameras())
        case "camera.snap":
            let params = request.decodedParams(as: CameraSnapParams.self)
            let result = try await CameraCapability.snap(
                camera: params?.camera,
                quality: params?.quality ?? 0.8,
                maxWidth: params?.maxWidth ?? 1920
            )
            return try encodeJSON(result)

        // Screen
        case "screen.snapshot":
            let params = request.decodedParams(as: ScreenSnapshotParams.self)
            let result = try await ScreenCapability.snapshot(
                maxWidth: params?.maxWidth ?? 1024,
                quality: params?.quality ?? 0.8
            )
            return try encodeJSON(result)

        // Canvas
        case "canvas.present":
            guard let params = request.decodedParams(as: CanvasPresentParams.self) else {
                throw NodeError.unavailable("Missing canvas URL")
            }
            let result = try await CanvasCapability.shared.present(url: params.url)
            return try encodeJSON(result)
        case "canvas.navigate":
            guard let params = request.decodedParams(as: CanvasPresentParams.self) else {
                throw NodeError.unavailable("Missing canvas URL")
            }
            let result = try await CanvasCapability.shared.navigate(url: params.url)
            return try encodeJSON(result)
        case "canvas.evalJS":
            guard let params = request.decodedParams(as: CanvasEvalParams.self) else {
                throw NodeError.unavailable("Missing JavaScript")
            }
            let result = try await CanvasCapability.shared.evalJS(script: params.script)
            return try encodeJSON(result)
        case "canvas.snapshot":
            let params = request.decodedParams(as: CanvasSnapshotParams.self)
            let result = try await CanvasCapability.shared.snapshot(
                maxWidth: params?.maxWidth ?? 1024,
                quality: params?.quality ?? 0.8
            )
            return try encodeJSON(result)
        case "canvas.reset":
            CanvasCapability.shared.reset()
            return "{\"ok\":true}"

        // Voice Wake
        case "voicewake.set":
            let params = request.decodedParams(as: VoiceWakeSetParams.self)
            let result = try await VoiceWakeCapability.shared.setConfig(
                keywords: params?.keywords ?? [],
                enabled: params?.enabled ?? true,
                locale: params?.locale
            )
            return try encodeJSON(result)
        case "voicewake.get":
            return try encodeJSON(VoiceWakeCapability.shared.getConfig())

        default:
            throw NodeError.unknownCommand(request.command)
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Protocol Types

struct NodeInvokeRequest: Decodable {
    let id: String
    let nodeId: String
    let command: String
    let paramsJSON: String?
    let timeoutMs: Int?
    let idempotencyKey: String?

    func decodedParams<T: Decodable>(as type: T.Type) -> T? {
        guard let json = paramsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct NodeInvokeResult: Encodable {
    let id: String
    let nodeId: String
    let ok: Bool
    let payloadJSON: String?
    let error: NodeInvokeError?
}

struct NodeInvokeError: Encodable {
    let code: String
    let message: String
}

enum NodeError: LocalizedError {
    case unknownCommand(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let cmd): return "Unknown command: \(cmd)"
        case .unavailable(let msg): return msg
        }
    }
}

// MARK: - System Notify Params

struct SystemNotifyParams: Decodable {
    let title: String?
    let body: String?
    let sound: String?
    let priority: String?
}
