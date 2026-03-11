import Foundation
import WebKit
import UIKit

/// Manages an agent-controlled WKWebView canvas.
/// Commands are dispatched from NodeConnection; the view is presented in CanvasView.
@Observable
@MainActor
final class CanvasCapability {

    struct PresentResult: Encodable { let ok: Bool }
    struct EvalResult: Encodable { let result: String? }
    struct SnapshotResult: Encodable {
        let imageBase64: String
        let width: Int
        let height: Int
    }

    enum CanvasError: LocalizedError {
        case noWebView
        case evalFailed(String)
        case snapshotFailed

        var errorDescription: String? {
            switch self {
            case .noWebView: return "Canvas not available — open the Canvas tab first"
            case .evalFailed(let msg): return "JavaScript error: \(msg)"
            case .snapshotFailed: return "Failed to capture canvas snapshot"
            }
        }
    }

    // MARK: - State

    private(set) var currentURL: String?
    var isPresented: Bool = false

    /// The WKWebView is set by CanvasView when it appears.
    var webView: WKWebView?
    private var pendingURL: URL?

    // MARK: - Singleton

    static let shared = CanvasCapability()
    private init() {}

    // MARK: - Commands

    func present(url: String) async throws -> PresentResult {
        guard let parsedURL = URL(string: url) else {
            throw CanvasError.evalFailed("Invalid URL: \(url)")
        }

        currentURL = url
        pendingURL = parsedURL
        isPresented = true

        // If webView already exists, load immediately
        if let webView {
            webView.load(URLRequest(url: parsedURL))
            pendingURL = nil
        }
        // Otherwise, CanvasView will pick up pendingURL when it creates the webView

        return PresentResult(ok: true)
    }

    /// Called by CanvasView when the WKWebView is created.
    func webViewReady(_ wv: WKWebView) {
        webView = wv
        if let url = pendingURL {
            wv.load(URLRequest(url: url))
            pendingURL = nil
        }
    }

    func navigate(url: String) async throws -> PresentResult {
        return try await present(url: url)
    }

    func evalJS(script: String) async throws -> EvalResult {
        guard let webView else { throw CanvasError.noWebView }

        let result = try await webView.evaluateJavaScript(script)
        let resultString: String?
        if let str = result as? String {
            resultString = str
        } else if let num = result as? NSNumber {
            resultString = num.stringValue
        } else if result is NSNull || result == nil {
            resultString = nil
        } else {
            resultString = String(describing: result)
        }

        return EvalResult(result: resultString)
    }

    func snapshot(maxWidth: Int = 1024, quality: Double = 0.8) async throws -> SnapshotResult {
        guard let webView else { throw CanvasError.noWebView }

        let config = WKSnapshotConfiguration()
        let image = try await webView.takeSnapshot(configuration: config)

        let resized = resizeImage(image, maxWidth: maxWidth)
        guard let jpegData = resized.jpegData(compressionQuality: quality) else {
            throw CanvasError.snapshotFailed
        }

        return SnapshotResult(
            imageBase64: jpegData.base64EncodedString(),
            width: Int(resized.size.width),
            height: Int(resized.size.height)
        )
    }

    func reset() {
        currentURL = nil
        webView?.loadHTMLString("", baseURL: nil)
    }

    // MARK: - Private

    private func resizeImage(_ image: UIImage, maxWidth: Int) -> UIImage {
        let maxW = CGFloat(maxWidth)
        if image.size.width <= maxW { return image }

        let scale = maxW / image.size.width
        let newSize = CGSize(width: maxW, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Params

struct CanvasPresentParams: Decodable {
    let url: String
}

struct CanvasEvalParams: Decodable {
    let script: String
}

struct CanvasSnapshotParams: Decodable {
    let maxWidth: Int?
    let quality: Double?
}
