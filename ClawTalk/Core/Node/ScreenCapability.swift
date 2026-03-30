import Foundation
import UIKit

enum ScreenCapability {

    struct SnapshotResult: Encodable {
        let imageBase64: String
        let width: Int
        let height: Int
    }

    enum ScreenError: LocalizedError {
        case noWindow
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .noWindow: return "No active window to capture"
            case .captureFailed: return "Screenshot capture failed"
            }
        }
    }

    @MainActor
    static func snapshot(maxWidth: Int = 1024, quality: Double = 0.8) async throws -> SnapshotResult {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else {
            throw ScreenError.noWindow
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        let resized = resizeImage(image, maxWidth: maxWidth)
        guard let jpegData = resized.jpegData(compressionQuality: quality) else {
            throw ScreenError.captureFailed
        }

        return SnapshotResult(
            imageBase64: jpegData.base64EncodedString(),
            width: Int(resized.size.width),
            height: Int(resized.size.height)
        )
    }

    private static func resizeImage(_ image: UIImage, maxWidth: Int) -> UIImage {
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

struct ScreenSnapshotParams: Decodable {
    let maxWidth: Int?
    let quality: Double?
}
