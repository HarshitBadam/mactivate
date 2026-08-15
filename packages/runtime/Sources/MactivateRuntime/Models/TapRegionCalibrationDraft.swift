import Foundation
import MactuationCore

public struct TapRegionCalibrationTarget: Hashable, Sendable {
    public var side: TapRegionSide
    public var pattern: TapRegionPattern

    public init(side: TapRegionSide, pattern: TapRegionPattern) {
        self.side = side
        self.pattern = pattern
    }

    public static let ordered: [TapRegionCalibrationTarget] =
        TapRegionSide.allCases.flatMap { side in
            TapRegionPattern.allCases.map {
                TapRegionCalibrationTarget(side: side, pattern: $0)
            }
        }
}

public enum TapRegionCalibrationRecordError: Error, Equatable,
    CustomStringConvertible {
    case wrongTapCount(expected: Int, detected: Int)
    case missingGyroscopeFeatures

    public var description: String {
        switch self {
        case .wrongTapCount(let expected, let detected):
            return "Detected \(detected) taps; this step needs \(expected). Try again."
        case .missingGyroscopeFeatures:
            return "Gyroscope data was unavailable for this gesture. Try again."
        }
    }
}

public struct TapRegionCalibrationDraft: Equatable, Sendable {
    public static let requiredGesturesPerTarget =
        TapRegionCalibrationProfileBuilder.requiredGesturesPerTarget

    private var gestures: [TapRegionCalibrationTarget:
        [TapRegionCalibrationGesture]] = [:]

    public init() {}

    public mutating func record(
        _ feedback: TapFeedback,
        target: TapRegionCalibrationTarget
    ) throws {
        guard feedback.memberCount == target.pattern.memberCount else {
            throw TapRegionCalibrationRecordError.wrongTapCount(
                expected: target.pattern.memberCount,
                detected: feedback.memberCount
            )
        }
        guard feedback.regionMemberFeatures.count ==
                target.pattern.memberCount else {
            throw TapRegionCalibrationRecordError.missingGyroscopeFeatures
        }
        let repetition = sampleCount(target: target) + 1
        gestures[target, default: []].append(TapRegionCalibrationGesture(
            side: target.side,
            pattern: target.pattern,
            repetition: repetition,
            memberFeatures: feedback.regionMemberFeatures
        ))
    }

    public func sampleCount(target: TapRegionCalibrationTarget) -> Int {
        gestures[target]?.count ?? 0
    }

    public var totalSampleCount: Int {
        gestures.values.reduce(0) { $0 + $1.count }
    }

    public var isComplete: Bool {
        TapRegionCalibrationTarget.ordered.allSatisfy {
            sampleCount(target: $0) >=
                Self.requiredGesturesPerTarget
        }
    }

    public mutating func reset(target: TapRegionCalibrationTarget) {
        gestures[target] = []
    }

    public mutating func reset() {
        gestures.removeAll()
    }

    public func buildProfile() throws -> TapRegionCalibrationBuildResult {
        try TapRegionCalibrationProfileBuilder.build(
            gestures: TapRegionCalibrationTarget.ordered.flatMap {
                gestures[$0] ?? []
            }
        )
    }
}

public typealias RuntimeTapRegionCalibrationProfile =
    TapRegionCalibrationProfile
