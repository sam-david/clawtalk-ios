import Foundation
import UIKit

@Observable
@MainActor
final class ToolsViewModel {
    // Memory
    var memoryResults: [MemorySearchEntry] = []
    var memoryFileContent: MemoryGetResult?
    var memorySearchQuery = ""

    // Agents
    var agents: [AgentEntry] = []

    // Sessions
    var sessions: [SessionEntry] = []
    var sessionStatus: String?
    var sessionHistory: SessionHistoryResult?

    // Browser
    var browserScreenshot: UIImage?
    var browserStatusText: String?
    var browserTabsText: String?

    // File
    var fileContent: String?
    var filePath = ""

    // Availability
    var toolAvailability: [ToolCategory: Bool] = [:]
    var availabilityChecked = false

    // Common
    var isLoading = false
    var errorMessage: String?

    private let client = OpenClawClient()
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var gatewayURL: String { settings.settings.gatewayURL }
    private var token: String { settings.gatewayToken }

    enum ToolCategory: String, CaseIterable {
        case memory, agents, sessions, browser, files
    }

    func isAvailable(_ category: ToolCategory) -> Bool {
        toolAvailability[category] ?? true
    }

    // MARK: - Availability Check

    func checkAvailability() async {
        guard !availabilityChecked else { return }
        availabilityChecked = true

        let probes: [(ToolCategory, String, String?, [String: JSONValue]?)] = [
            (.memory, "memory_search", nil, ["query": .string("test"), "maxResults": .int(1)]),
            (.agents, "agents_list", nil, nil),
            (.sessions, "sessions_list", nil, ["limit": .int(1)]),
            (.browser, "browser", "status", nil),
            (.files, "read", nil, ["path": .string(".")]),
        ]

        await withTaskGroup(of: (ToolCategory, Bool).self) { group in
            for (category, tool, action, args) in probes {
                group.addTask { [client, gatewayURL, token] in
                    do {
                        _ = try await client.invokeTool(
                            tool: tool,
                            action: action,
                            args: args,
                            gatewayURL: gatewayURL,
                            token: token
                        )
                        return (category, true)
                    } catch let error as OpenClawError {
                        if case .toolNotFound = error {
                            return (category, false)
                        }
                        // Any other error means the tool exists but something else went wrong
                        return (category, true)
                    } catch {
                        return (category, true)
                    }
                }
            }

            for await (category, available) in group {
                toolAvailability[category] = available
            }
        }
    }

    // MARK: - Memory

    func searchMemory() async {
        let query = memorySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "memory_search",
                args: [
                    "query": .string(query),
                    "maxResults": .int(20)
                ],
                gatewayURL: gatewayURL,
                token: token
            )
            // Result is {content, details} — details has the structured data
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<MemorySearchResults>.self, from: data)
            memoryResults = wrapper.details?.results ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getMemoryFile(path: String, from: Int? = nil, lines: Int? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            var args: [String: JSONValue] = ["path": .string(path)]
            if let from { args["from"] = .int(from) }
            if let lines { args["lines"] = .int(lines) }

            let data = try await client.invokeTool(
                tool: "memory_get",
                args: args,
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<MemoryGetResult>.self, from: data)
            memoryFileContent = wrapper.details
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Agents

    func listAgents() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "agents_list",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<AgentsListResult>.self, from: data)
            agents = wrapper.details?.agents ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Sessions

    func listSessions() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "sessions_list",
                args: ["limit": .int(50)],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionsListResult>.self, from: data)
            sessions = wrapper.details?.sessions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getSessionStatus(sessionKey: String? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            var args: [String: JSONValue]?
            if let sessionKey {
                args = ["sessionKey": .string(sessionKey)]
            }

            let data = try await client.invokeTool(
                tool: "session_status",
                args: args,
                gatewayURL: gatewayURL,
                token: token
            )
            // session_status returns text in content and details
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionStatusResult.StatusDetails>.self, from: data)
            sessionStatus = wrapper.details?.statusText
                ?? wrapper.content?.first?.text
                ?? "No status available"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getSessionHistory(sessionKey: String, limit: Int = 20) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "sessions_history",
                args: [
                    "sessionKey": .string(sessionKey),
                    "limit": .int(limit)
                ],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<SessionHistoryResult>.self, from: data)
            sessionHistory = wrapper.details
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Browser

    func getBrowserStatus() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "status",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            browserStatusText = wrapper.content?.first?.text ?? "No status"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func takeBrowserScreenshot() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "screenshot",
                args: ["type": .string("jpeg")],
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            if let imageItem = wrapper.content?.first(where: { $0.type == "image" }),
               let base64 = imageItem.image?.data,
               let decoded = Data(base64Encoded: base64) {
                browserScreenshot = UIImage(data: decoded)
            } else if let textContent = wrapper.content?.first?.text,
                      let decoded = Data(base64Encoded: textContent) {
                browserScreenshot = UIImage(data: decoded)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func getBrowserTabs() async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "browser",
                action: "tabs",
                gatewayURL: gatewayURL,
                token: token
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<BrowserDetails>.self, from: data)
            browserTabsText = wrapper.content?.first?.text ?? "No tabs"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Files

    func readFile(path: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let data = try await client.invokeTool(
                tool: "read",
                args: ["path": .string(path)],
                gatewayURL: gatewayURL,
                token: token
            )
            // read tool returns {content: [{type: "text", text: "..."}]}
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<JSONValue>.self, from: data)
            if let text = wrapper.content?.first?.text {
                fileContent = text
            } else if let text = String(data: data, encoding: .utf8) {
                let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                fileContent = cleaned
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
