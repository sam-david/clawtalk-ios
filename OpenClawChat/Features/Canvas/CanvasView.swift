import SwiftUI
import WebKit

/// Hosts the agent-controlled WKWebView canvas.
/// The agent can load URLs, execute JavaScript, and take snapshots.
struct CanvasView: View {
    var canvas: CanvasCapability
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebViewRepresentable(canvas: canvas)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(canvas.currentURL ?? "Canvas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let url = canvas.currentURL {
                            Button(action: {
                                UIPasteboard.general.string = url
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                }
        }
    }
}

// MARK: - WKWebView UIViewRepresentable

private struct WebViewRepresentable: UIViewRepresentable {
    var canvas: CanvasCapability

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true

        // Register the webView with the canvas capability
        canvas.webView = webView

        if let url = canvas.currentURL, let parsedURL = URL(string: url) {
            webView.load(URLRequest(url: parsedURL))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep canvas reference updated
        if canvas.webView !== webView {
            canvas.webView = webView
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        // Don't nil out canvas.webView here — it may still be needed
    }
}
