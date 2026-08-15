import Foundation
import MactuationCore

public enum TapCalibrationSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right

    var coreValue: PalmSide {
        switch self {
        case .left: return .left
        case .right: return .right
        }
    }
}

public enum TapCalibrationIntensity: String, CaseIterable, Hashable, Sendable {
    case comfort
    case firm

    var coreValue: TapCalibrationForce {
        switch self {
        case .comfort: return .comfort
        case .firm: return .firm
        }
    }
}

public struct TapCalibrationTarget: Hashable, Sendable {
    public var side: TapCalibrationSide
    public var intensity: TapCalibrationIntensity

    public init(
        side: TapCalibrationSide,
        intensity: TapCalibrationIntensity
    ) {
        self.side = side
        self.intensity = intensity
    }
}

public enum TapCalibrationRecordError: Error, Equatable,
    CustomStringConvertible {
    case wrongTapCount(detected: Int)
    case rejected(TapRejectionReason)
    case wrongIntensity(expected: TapCalibrationIntensity)
    case invalidOutcome

    public var description: String {
        switch self {
        case .wrongTapCount(let detected):
            return "Not recorded: perform one tap, not \(detected)."
        case .rejected(let reason):
            return "Not recorded. \(reason.guidance)"
        case .wrongIntensity(let expected):
            return "Not recorded: use a clearly \(expected.rawValue) tap."
        case .invalidOutcome:
            return "Not recorded: the tap did not produce a complete decision."
        }
    }
}

public struct TapCalibrationDraft: Equatable, Sendable {
    public static let requiredSamplesPerTarget = 5

    private var comfort: [PalmSide: [TapEventFeatures]] = [:]
    private var firm: [PalmSide: [TapEventFeatures]] = [:]

    public init() {}

    public mutating func record(
        _ feedback: TapFeedback,
        side: TapCalibrationSide,
        intensity: TapCalibrationIntensity
    ) throws {
        guard feedback.memberCount == 1 else {
            throw TapCalibrationRecordError.wrongTapCount(
                detected: feedback.memberCount
            )
        }
        switch intensity {
        case .comfort:
            guard feedback.outcome == .acceptedNonActionable(.single) else {
                if case .rejected(let reason) = feedback.outcome {
                    throw TapCalibrationRecordError.rejected(reason)
                }
                throw TapCalibrationRecordError.invalidOutcome
            }
            guard feedback.acceptanceVerdict == .acceptedComfort,
                  feedback.features.zImpulseMgS > 0 else {
                throw TapCalibrationRecordError.wrongIntensity(
                    expected: .comfort
                )
            }
        case .firm:
            switch feedback.outcome {
            case .acceptedNonActionable(.single):
                guard let verdict = feedback.acceptanceVerdict else {
                    throw TapCalibrationRecordError.invalidOutcome
                }
                switch verdict {
                case .acceptedComfort, .acceptedFirm:
                    break
                case .rejected:
                    throw TapCalibrationRecordError.invalidOutcome
                }
            case .rejected(.comfortZImpulse):
                break
            case .rejected(let reason):
                throw TapCalibrationRecordError.rejected(reason)
            default:
                throw TapCalibrationRecordError.invalidOutcome
            }
        }
        guard sampleCount(side: side, intensity: intensity) <
                Self.requiredSamplesPerTarget else {
            return
        }
        switch intensity {
        case .comfort:
            comfort[side.coreValue, default: []].append(feedback.features)
        case .firm:
            firm[side.coreValue, default: []].append(feedback.features)
        }
    }

    public func sampleCount(
        side: TapCalibrationSide,
        intensity: TapCalibrationIntensity
    ) -> Int {
        switch intensity {
        case .comfort:
            return comfort[side.coreValue]?.count ?? 0
        case .firm:
            return firm[side.coreValue]?.count ?? 0
        }
    }

    public mutating func reset(
        side: TapCalibrationSide,
        intensity: TapCalibrationIntensity
    ) {
        switch intensity {
        case .comfort:
            comfort[side.coreValue] = []
        case .firm:
            firm[side.coreValue] = []
        }
    }

    public mutating func reset() {
        comfort.removeAll()
        firm.removeAll()
    }

    public func buildProfile() throws -> TapCalibrationProfile {
        try TapCalibrationProfileBuilder.build(
            comfort: comfort,
            firm: firm
        )
    }
}

public typealias RuntimeTapCalibrationProfile = TapCalibrationProfile
