import SwiftUI
import MarkdownUI

extension Color {
    /// OpenClaw brand red — warm, slightly orange-tinted red like a lobster
    static let openClawRed = Color(red: 0.85, green: 0.18, blue: 0.15)

    /// Darker variant for gradients / pressed states
    static let openClawDarkRed = Color(red: 0.65, green: 0.12, blue: 0.10)
}

extension ShapeStyle where Self == Color {
    static var openClawRed: Color { .openClawRed }
}

// MARK: - Markdown Theme

extension MarkdownUI.Theme {
    static let openClaw = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(14)
            ForegroundColor(.secondary)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                    }
                    .padding(12)
            }
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .markdownMargin(top: 8, bottom: 8)
        }
        .link {
            ForegroundColor(.openClawRed)
        }
        .strong {
            FontWeight(.semibold)
        }
}
