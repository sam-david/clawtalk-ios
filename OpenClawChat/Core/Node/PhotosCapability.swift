import Foundation
import Photos
import UIKit

enum PhotosCapability {

    struct PhotoResult: Encodable {
        let identifier: String
        let creationDate: String?
        let width: Int
        let height: Int
        let mediaType: String
        let imageBase64: String?
    }

    enum PhotosError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Photos permission denied"
            case .failed(let msg): return msg
            }
        }
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func getLatest(count: Int = 5, includeImage: Bool = true, maxWidth: Int = 1024) async throws -> [PhotoResult] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotosError.denied
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = count

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var results: [PhotoResult] = []
        let imageManager = PHImageManager.default()

        for i in 0..<assets.count {
            let asset = assets[i]
            var imageBase64: String?

            if includeImage {
                let targetSize = CGSize(
                    width: min(maxWidth, asset.pixelWidth),
                    height: min(maxWidth, asset.pixelHeight)
                )

                let requestOptions = PHImageRequestOptions()
                requestOptions.deliveryMode = .highQualityFormat
                requestOptions.isSynchronous = false
                requestOptions.resizeMode = .exact

                imageBase64 = try await withCheckedThrowingContinuation { continuation in
                    imageManager.requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFit,
                        options: requestOptions
                    ) { image, _ in
                        if let image, let data = image.jpegData(compressionQuality: 0.8) {
                            continuation.resume(returning: data.base64EncodedString())
                        } else {
                            continuation.resume(returning: nil as String?)
                        }
                    }
                }
            }

            results.append(PhotoResult(
                identifier: asset.localIdentifier,
                creationDate: asset.creationDate.map { formatter.string(from: $0) },
                width: asset.pixelWidth,
                height: asset.pixelHeight,
                mediaType: asset.mediaType == .video ? "video" : "image",
                imageBase64: imageBase64
            ))
        }

        return results
    }
}

// MARK: - Params

struct PhotosLatestParams: Decodable {
    let count: Int?
    let includeImage: Bool?
    let maxWidth: Int?
}
