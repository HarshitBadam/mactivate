import Foundation

public enum TapCalibrationForce: String, Codable, CaseIterable, Sendable {
    case comfort
    case firm
}

public struct TapCalibrationSideSummary: Codable, Equatable, Sendable {
    public var comfortSampleCount: Int
    public var firmSampleCount: Int
    public var comfortPeakMedianG: Double
    public var firmPeakMedianG: Double
    public var zImpulseMedianMgS: Double

    public init(
        comfortSampleCount: Int,
        firmSampleCount: Int,
        comfortPeakMedianG: Double,
        firmPeakMedianG: Double,
        zImpulseMedianMgS: Double
    ) {
        self.comfortSampleCount = comfortSampleCount
        self.firmSampleCount = firmSampleCount
        self.comfortPeakMedianG = comfortPeakMedianG
        self.firmPeakMedianG = firmPeakMedianG
        self.zImpulseMedianMgS = zImpulseMedianMgS
    }
}

public struct TapCalibrationProfile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var identifier: UUID
    public var createdAt: Date
    public var calibration: TapCalibration
    public var sideSummaries: [PalmSide: TapCalibrationSideSummary]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        identifier: UUID = UUID(),
        createdAt: Date = Date(),
        calibration: TapCalibration,
        sideSummaries: [PalmSide: TapCalibrationSideSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.createdAt = createdAt
        self.calibration = calibration
        self.sideSummaries = sideSummaries
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion &&
            calibration.version.hasPrefix("personal-spatial-") &&
            calibration.detrendWindowS ==
                TapCalibration.mac14_2SpatialMultiTap.detrendWindowS &&
            calibration.refractoryS ==
                TapCalibration.mac14_2SpatialMultiTap.refractoryS &&
            calibration.groupGapS ==
                TapCalibration.mac14_2SpatialMultiTap.groupGapS &&
            calibration.maxGroupMembers ==
                TapCalibration.mac14_2SpatialMultiTap.maxGroupMembers &&
            calibration.impulseHalfWindowS ==
                TapCalibration.mac14_2SpatialMultiTap.impulseHalfWindowS &&
            calibration.comfortLateralVetoMgS ==
                TapCalibration.mac14_2SpatialMultiTap.comfortLateralVetoMgS &&
            calibration.eventThresholdG.isFinite &&
            calibration.eventThresholdG >= 0.02 &&
            calibration.eventThresholdG <=
                TapCalibration.mac14_2SpatialMultiTap.eventThresholdG &&
            Set(calibration.firmTiers.keys) == Set(PalmSide.allCases) &&
            calibration.firmTiers.values.allSatisfy {
                $0.amplitudeCutG.isFinite &&
                    $0.amplitudeCutG >= 0.08 &&
                    $0.amplitudeCutG <=
                        TapCalibration.mac14_2SpatialMultiTap
                            .firmTiers[.left]!.amplitudeCutG &&
                    $0.lateralToPeakMaxMgSPerG ==
                        TapCalibration.mac14_2SpatialMultiTap
                            .firmTiers[.left]!.lateralToPeakMaxMgSPerG &&
                    $0.decayMaxMs ==
                        TapCalibration.mac14_2SpatialMultiTap
                            .firmTiers[.left]!.decayMaxMs
            } &&
            Set(sideSummaries.keys) == Set(PalmSide.allCases) &&
            sideSummaries.values.allSatisfy {
                $0.comfortSampleCount >= 5 && $0.firmSampleCount >= 5
            }
    }
}

public enum TapCalibrationProfileError: Error, Equatable, CustomStringConvertible {
    case insufficientSamples(side: PalmSide, force: TapCalibrationForce)
    case invalidFeatures(side: PalmSide, force: TapCalibrationForce)
    case inconsistentComfortDirection(side: PalmSide)

    public var description: String {
        switch self {
        case .insufficientSamples(let side, let force):
            return "Capture at least 5 \(force.rawValue) taps on the \(side.rawValue) palm rest."
        case .invalidFeatures(let side, let force):
            return "The \(side.rawValue) \(force.rawValue) samples were not consistent enough to calibrate."
        case .inconsistentComfortDirection(let side):
            return "Redo the \(side.rawValue) comfort taps. Tap straight down without sliding so at least four of five impulses match the safe palm-tap direction."
        }
    }
}
