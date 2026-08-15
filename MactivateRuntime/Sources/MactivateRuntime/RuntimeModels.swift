import Foundation
import MactuationCore

public struct ActionIdentifier: RawRepresentable, Codable, Equatable, Hashable,
    Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var isValid: Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 256
    }
}

public enum TapPattern: Int, Codable, CaseIterable, Hashable, Sendable {
    case single = 1
    case double = 2
    case triple = 3
}

public struct TapBindings: Codable, Equatable, Sendable {
    public var single: ActionIdentifier?
    public var double: ActionIdentifier?
    public var triple: ActionIdentifier?

    public init(single: ActionIdentifier? = nil,
                double: ActionIdentifier? = nil,
                triple: ActionIdentifier? = nil) {
        self.single = single
        self.double = double
        self.triple = triple
    }

    public subscript(pattern: TapPattern) -> ActionIdentifier? {
        get {
            switch pattern {
            case .single: return single
            case .double: return double
            case .triple: return triple
            }
        }
        set {
            switch pattern {
            case .single: single = newValue
            case .double: double = newValue
            case .triple: triple = newValue
            }
        }
    }

    var isValid: Bool {
        [single, double, triple].compactMap { $0 }.allSatisfy(\.isValid)
    }
}

public struct PalmTapGesture: Codable, Equatable, Hashable, Sendable {
    public var side: TapRegionSide
    public var pattern: TapRegionPattern

    public init(side: TapRegionSide, pattern: TapRegionPattern) {
        self.side = side
        self.pattern = pattern
    }

    public static let leftDouble = PalmTapGesture(
        side: .left,
        pattern: .double
    )
    public static let leftTriple = PalmTapGesture(
        side: .left,
        pattern: .triple
    )
    public static let rightDouble = PalmTapGesture(
        side: .right,
        pattern: .double
    )
    public static let rightTriple = PalmTapGesture(
        side: .right,
        pattern: .triple
    )

    public static let allCases: [PalmTapGesture] = [
        .leftDouble,
        .leftTriple,
        .rightDouble,
        .rightTriple
    ]
}

public struct SpatialTapBindings: Codable, Equatable, Sendable {
    public var leftDouble: ActionIdentifier?
    public var leftTriple: ActionIdentifier?
    public var rightDouble: ActionIdentifier?
    public var rightTriple: ActionIdentifier?

    public init(
        leftDouble: ActionIdentifier? = nil,
        leftTriple: ActionIdentifier? = nil,
        rightDouble: ActionIdentifier? = nil,
        rightTriple: ActionIdentifier? = nil
    ) {
        self.leftDouble = leftDouble
        self.leftTriple = leftTriple
        self.rightDouble = rightDouble
        self.rightTriple = rightTriple
    }

    public subscript(gesture: PalmTapGesture) -> ActionIdentifier? {
        get {
            switch (gesture.side, gesture.pattern) {
            case (.left, .double): return leftDouble
            case (.left, .triple): return leftTriple
            case (.right, .double): return rightDouble
            case (.right, .triple): return rightTriple
            }
        }
        set {
            switch (gesture.side, gesture.pattern) {
            case (.left, .double): leftDouble = newValue
            case (.left, .triple): leftTriple = newValue
            case (.right, .double): rightDouble = newValue
            case (.right, .triple): rightTriple = newValue
            }
        }
    }

    public var isEmpty: Bool {
        PalmTapGesture.allCases.allSatisfy { self[$0] == nil }
    }

    var isValid: Bool {
        PalmTapGesture.allCases.compactMap { self[$0] }
            .allSatisfy(\.isValid)
    }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var spatialTapBindings: SpatialTapBindings
    public var spatialTapDispatchEnabled: Bool
    public var panelHintsEnabled: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        spatialTapBindings: SpatialTapBindings = SpatialTapBindings(),
        spatialTapDispatchEnabled: Bool = true,
        panelHintsEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.spatialTapBindings = spatialTapBindings
        self.spatialTapDispatchEnabled = spatialTapDispatchEnabled
        self.panelHintsEnabled = panelHintsEnabled
    }

    public static let `default` = RuntimeConfiguration()

    public static let failClosed = RuntimeConfiguration(
        spatialTapBindings: SpatialTapBindings(),
        spatialTapDispatchEnabled: false,
        panelHintsEnabled: false
    )

    var isCurrentAndValid: Bool {
        schemaVersion == Self.currentSchemaVersion && spatialTapBindings.isValid
    }
}

public struct RuntimeEventID: Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let classifierEventID: String

    public init(sessionID: UUID, classifierEventID: String) {
        self.sessionID = sessionID
        self.classifierEventID = classifierEventID
    }
}

public struct TapTrigger: Equatable, Sendable {
    public let eventID: RuntimeEventID
    public let gesture: PalmTapGesture
    public let sensorTimestamp: SensorTimestamp
    public let regionProfileVersion: String

    public init(
        eventID: RuntimeEventID,
        gesture: PalmTapGesture,
        sensorTimestamp: SensorTimestamp,
        regionProfileVersion: String
    ) {
        self.eventID = eventID
        self.gesture = gesture
        self.sensorTimestamp = sensorTimestamp
        self.regionProfileVersion = regionProfileVersion
    }

    public var pattern: TapPattern {
        gesture.pattern == .double ? .double : .triple
    }
}

public enum SpatialTapUnavailableReason: Equatable, Sendable {
    case tapCalibrationRequired
    case calibrationRequired
    case gyroscopeUnavailable
    case insufficientGyroscopeData
    case ambiguous
    case invalidProfile

    public var message: String {
        switch self {
        case .tapCalibrationRequired:
            return "tap-acceptance calibration required"
        case .calibrationRequired:
            return "left/right calibration required"
        case .gyroscopeUnavailable:
            return "gyroscope unavailable"
        case .insufficientGyroscopeData:
            return "incomplete gyroscope window"
        case .ambiguous:
            return "side was inside the confidence guard band"
        case .invalidProfile:
            return "left/right calibration is invalid"
        }
    }
}

public enum TapFeedbackOutcome: Equatable, Sendable {
    case candidate
    case rejected(TapRejectionReason)
    case acceptedNonActionable(TapPattern)
    case acceptedUnmapped(PalmTapGesture)
    case dispatchDisabled(PalmTapGesture)
    case duplicate(PalmTapGesture)
    case spatialUnavailable(pattern: TapRegionPattern,
                            reason: SpatialTapUnavailableReason)
    case dispatched(gesture: PalmTapGesture, action: ActionIdentifier)
}

public struct TapFeedback: Equatable, Sendable {
    public let outcome: TapFeedbackOutcome
    public let acceptanceVerdict: TapVerdict?
    public let memberCount: Int
    public let features: TapEventFeatures
    public let sensorTimestamp: SensorTimestamp
    public let resolutionLatencyS: Double
    public let regionPrediction: TapRegionPrediction?
    public let regionMemberFeatures: [Double]
    public let regionFeature: Double?
    public let regionProfileVersion: String?
    public let regionReason: TapRegionResolutionReason?

    public init(
        outcome: TapFeedbackOutcome,
        acceptanceVerdict: TapVerdict? = nil,
        memberCount: Int,
        features: TapEventFeatures,
        sensorTimestamp: SensorTimestamp,
        resolutionLatencyS: Double,
        regionPrediction: TapRegionPrediction? = nil,
        regionMemberFeatures: [Double] = [],
        regionFeature: Double? = nil,
        regionProfileVersion: String? = nil,
        regionReason: TapRegionResolutionReason? = nil
    ) {
        self.outcome = outcome
        self.acceptanceVerdict = acceptanceVerdict
        self.memberCount = memberCount
        self.features = features
        self.sensorTimestamp = sensorTimestamp
        self.resolutionLatencyS = resolutionLatencyS
        self.regionPrediction = regionPrediction
        self.regionMemberFeatures = regionMemberFeatures
        self.regionFeature = regionFeature
        self.regionProfileVersion = regionProfileVersion
        self.regionReason = regionReason
    }
}

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

public enum PanelPresentationReason: Equatable, Sendable {
    case ambientLightHint
}

public enum RuntimeIntent: Equatable, Sendable {
    case performAction(id: ActionIdentifier, trigger: TapTrigger)
    case showPanel(reason: PanelPresentationReason, hint: PanelOpenHint)
}

public enum RuntimeLifecycleState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case suspended
    case stopping
}

public enum TapFeatureState: Equatable, Sendable {
    case inactive
    case warmingUp
    case available(measuredRateHz: Double)
    case unavailable(reason: String)
}

public enum TapRegionFeatureState: Equatable, Sendable {
    case inactive
    case warmingUp
    case needsCalibration
    case available(profileVersion: String)
    case unavailable(reason: String)
}

public enum PanelHintFeatureState: Equatable, Sendable {
    case inactive
    case disabled
    case warmingUp
    case available
    case tooDim
    case unavailable(reason: String)
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public var lifecycle: RuntimeLifecycleState
    public var tap: TapFeatureState
    public var tapRegion: TapRegionFeatureState
    public var panelHint: PanelHintFeatureState

    public init(
        lifecycle: RuntimeLifecycleState = .stopped,
        tap: TapFeatureState = .inactive,
        tapRegion: TapRegionFeatureState = .inactive,
        panelHint: PanelHintFeatureState = .inactive
    ) {
        self.lifecycle = lifecycle
        self.tap = tap
        self.tapRegion = tapRegion
        self.panelHint = panelHint
    }
}

public enum RuntimeWarning: Equatable, Sendable {
    case configuration(String)
    case source(path: SensorPath?, message: String)
}

public enum RuntimeOutput: Equatable, Sendable {
    case statusChanged(RuntimeSnapshot)
    case tapFeedback(TapFeedback)
    case intent(RuntimeIntent)
    case warning(RuntimeWarning)
}
