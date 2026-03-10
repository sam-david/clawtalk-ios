import Foundation
import CoreMotion

enum MotionCapability {

    struct ActivityResult: Encodable {
        let stationary: Bool
        let walking: Bool
        let running: Bool
        let cycling: Bool
        let automotive: Bool
        let unknown: Bool
        let confidence: String
        let startDate: String
    }

    struct PedometerResult: Encodable {
        let steps: Int
        let distance: Double?
        let floorsAscended: Int?
        let floorsDescended: Int?
        let startDate: String
        let endDate: String
    }

    enum MotionError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let msg): return msg
            }
        }
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Activity

    static func getActivity(hours: Int = 1) async throws -> [ActivityResult] {
        guard CMMotionActivityManager.isActivityAvailable() else {
            throw MotionError.unavailable("Motion activity not available")
        }

        let manager = CMMotionActivityManager()
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hours, to: now)!

        let activities = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CMMotionActivity], Error>) in
            manager.queryActivityStarting(from: start, to: now, to: .main) { activities, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: activities ?? [])
                }
            }
        }

        return activities.map { activity in
            let confidence: String = switch activity.confidence {
            case .low: "low"
            case .medium: "medium"
            case .high: "high"
            @unknown default: "unknown"
            }

            return ActivityResult(
                stationary: activity.stationary,
                walking: activity.walking,
                running: activity.running,
                cycling: activity.cycling,
                automotive: activity.automotive,
                unknown: activity.unknown,
                confidence: confidence,
                startDate: formatter.string(from: activity.startDate)
            )
        }
    }

    // MARK: - Pedometer

    static func getPedometer(hours: Int = 24) async throws -> PedometerResult {
        guard CMPedometer.isStepCountingAvailable() else {
            throw MotionError.unavailable("Pedometer not available")
        }

        let pedometer = CMPedometer()
        let now = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -hours, to: now)!

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CMPedometerData, Error>) in
            pedometer.queryPedometerData(from: start, to: now) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MotionError.unavailable("No pedometer data"))
                }
            }
        }

        return PedometerResult(
            steps: data.numberOfSteps.intValue,
            distance: data.distance?.doubleValue,
            floorsAscended: data.floorsAscended?.intValue,
            floorsDescended: data.floorsDescended?.intValue,
            startDate: formatter.string(from: start),
            endDate: formatter.string(from: now)
        )
    }
}

// MARK: - Params

struct MotionActivityParams: Decodable {
    let hours: Int?
}

struct MotionPedometerParams: Decodable {
    let hours: Int?
}
