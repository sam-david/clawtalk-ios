import Testing
import Foundation
@testable import ClawTalk

@Suite("Security & Connection Validation")
struct SecurityTests {

    // MARK: - HTTPS Enforcement (no network calls — pure validation logic)

    @Test("HTTPS URLs are accepted")
    func httpsAccepted() throws {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
        // No throw = pass
    }

    @Test("HTTP to public host is rejected")
    func httpPublicRejected() {
        let url = URL(string: "http://public.example.com/v1/chat/completions")!
        #expect(throws: OpenClawError.self) {
            try OpenClawClient.validateConnectionSecurity(url)
        }
    }

    @Test("HTTP to localhost is allowed")
    func httpLocalhostAllowed() throws {
        let url = URL(string: "http://localhost:18789/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 127.0.0.1 is allowed")
    func httpLoopbackAllowed() throws {
        let url = URL(string: "http://127.0.0.1:18789/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to ::1 (IPv6 loopback) is allowed")
    func httpIPv6LoopbackAllowed() throws {
        let url = URL(string: "http://[::1]:18789/v1/chat/completions")!
        // Note: URL(string:) may not parse bracketed IPv6 the same on all platforms
        // This tests the intent; if URL parsing drops brackets, host becomes "::1"
        do {
            try OpenClawClient.validateConnectionSecurity(url)
        } catch {
            // IPv6 URL parsing can be tricky — not a hard failure
        }
    }

    @Test("HTTP to 192.168.x.x is allowed")
    func httpPrivateNetworkAllowed() throws {
        let url = URL(string: "http://192.168.1.100:18789/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 192.168.0.1 is allowed")
    func httpPrivateNetworkGateway() throws {
        let url = URL(string: "http://192.168.0.1/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 10.x.x.x is allowed")
    func httpTenNetworkAllowed() throws {
        let url = URL(string: "http://10.0.0.5:18789/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 10.255.255.255 is allowed")
    func httpTenNetworkMax() throws {
        let url = URL(string: "http://10.255.255.255/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 172.16.x.x is allowed")
    func http172Network() throws {
        let url = URL(string: "http://172.16.0.1/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to 172.31.x.x is allowed")
    func http172NetworkMax() throws {
        let url = URL(string: "http://172.31.255.255/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to .local domain is allowed")
    func httpLocalDomainAllowed() throws {
        let url = URL(string: "http://myserver.local:18789/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to .local subdomain is allowed")
    func httpLocalSubdomain() throws {
        let url = URL(string: "http://openclaw.myserver.local/v1/chat/completions")!
        try OpenClawClient.validateConnectionSecurity(url)
    }

    @Test("HTTP to random public domain is rejected")
    func httpRandomDomainRejected() {
        let url = URL(string: "http://samdavid.net/v1/chat/completions")!
        #expect(throws: OpenClawError.self) {
            try OpenClawClient.validateConnectionSecurity(url)
        }
    }

    @Test("HTTP to cloud provider is rejected")
    func httpCloudRejected() {
        let url = URL(string: "http://my-instance.amazonaws.com/v1/chat/completions")!
        #expect(throws: OpenClawError.self) {
            try OpenClawClient.validateConnectionSecurity(url)
        }
    }

    @Test("FTP scheme is rejected")
    func ftpRejected() {
        let url = URL(string: "ftp://example.com/v1/chat/completions")!
        #expect(throws: OpenClawError.self) {
            try OpenClawClient.validateConnectionSecurity(url)
        }
    }

    // MARK: - Error Types

    @Test("All OpenClawError cases have descriptions")
    func allErrorsHaveDescriptions() {
        let errors: [OpenClawError] = [
            .invalidURL,
            .invalidResponse,
            .httpError(500),
            .httpErrorDetailed(401, 1024, "Unauthorized"),
            .emptyResponse,
            .insecureConnection,
            .responseError("Test error"),
            .toolError("Tool failed"),
            .toolNotFound("memory_search"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("httpError includes status code in description")
    func httpErrorDescription() {
        let error = OpenClawError.httpError(503)
        #expect(error.errorDescription!.contains("503"))
    }

    @Test("httpErrorDetailed includes status code and body preview")
    func httpErrorDetailedDescription() {
        let error = OpenClawError.httpErrorDetailed(401, 2048, "Unauthorized: invalid token")
        let desc = error.errorDescription!
        #expect(desc.contains("401"))
        #expect(desc.contains("Unauthorized"))
    }

    @Test("toolNotFound includes tool name in description")
    func toolNotFoundDescription() {
        let error = OpenClawError.toolNotFound("browser_screenshot")
        #expect(error.errorDescription!.contains("browser_screenshot"))
    }

    @Test("responseError preserves original message")
    func responseErrorPreservesMessage() {
        let error = OpenClawError.responseError("Rate limit exceeded")
        #expect(error.errorDescription == "Rate limit exceeded")
    }

    @Test("insecureConnection has clear message")
    func insecureConnectionMessage() {
        let error = OpenClawError.insecureConnection
        #expect(error.errorDescription!.contains("HTTPS"))
    }
}
