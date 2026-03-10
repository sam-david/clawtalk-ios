import Foundation
import AVFoundation
import UIKit

enum CameraCapability {

    struct CameraInfo: Encodable {
        let id: String
        let position: String
        let deviceType: String
    }

    struct SnapResult: Encodable {
        let imageBase64: String
        let width: Int
        let height: Int
        let camera: String
    }

    enum CameraError: LocalizedError {
        case denied
        case unavailable(String)
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Camera permission denied"
            case .unavailable(let msg): return msg
            case .captureFailed(let msg): return msg
            }
        }
    }

    // MARK: - List Cameras

    static func listCameras() -> [CameraInfo] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )

        return discoverySession.devices.map { device in
            let position: String = switch device.position {
            case .front: "front"
            case .back: "back"
            case .unspecified: "unspecified"
            @unknown default: "unknown"
            }

            return CameraInfo(
                id: device.uniqueID,
                position: position,
                deviceType: device.deviceType.rawValue
            )
        }
    }

    // MARK: - Take Photo

    static func snap(
        camera: String? = nil,
        quality: Double = 0.8,
        maxWidth: Int = 1920
    ) async throws -> SnapResult {
        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.denied }
        } else if status == .denied || status == .restricted {
            throw CameraError.denied
        }

        // Find camera device
        let position: AVCaptureDevice.Position = camera == "front" ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.unavailable("No \(camera ?? "back") camera available")
        }

        // Set up capture session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw CameraError.unavailable("Cannot access camera input")
        }
        guard session.canAddInput(input) else {
            throw CameraError.unavailable("Cannot add camera input to session")
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraError.unavailable("Cannot add photo output to session")
        }
        session.addOutput(output)

        // Start session and capture
        session.startRunning()

        // Small delay to let camera warm up
        try await Task.sleep(nanoseconds: 500_000_000)

        let delegate = PhotoCaptureDelegate()
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: delegate)

        let photoData = try await delegate.waitForCapture()
        session.stopRunning()

        guard let image = UIImage(data: photoData) else {
            throw CameraError.captureFailed("Failed to create image from capture data")
        }

        // Resize if needed
        let resized = resizeImage(image, maxWidth: maxWidth)
        guard let jpegData = resized.jpegData(compressionQuality: quality) else {
            throw CameraError.captureFailed("Failed to encode JPEG")
        }

        return SnapResult(
            imageBase64: jpegData.base64EncodedString(),
            width: Int(resized.size.width),
            height: Int(resized.size.height),
            camera: camera ?? "back"
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

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data, Error>?

    func waitForCapture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CameraCapability.CameraError.captureFailed("No photo data"))
        }
        continuation = nil
    }
}

// MARK: - Params

struct CameraSnapParams: Decodable {
    let camera: String?
    let quality: Double?
    let maxWidth: Int?
}
