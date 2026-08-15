import Foundation

public enum TapCalibrationProfileBuilder {
    public static func build(
        comfort: [PalmSide: [TapEventFeatures]],
        firm: [PalmSide: [TapEventFeatures]]
    ) throws -> TapCalibrationProfile {
        var summaries: [PalmSide: TapCalibrationSideSummary] = [:]
        var firmTiers: [PalmSide: TapCalibration.FirmTier] = [:]
        var allComfort: [TapEventFeatures] = []

        for side in PalmSide.allCases {
            let comfortValues = comfort[side] ?? []
            let firmValues = firm[side] ?? []
            guard comfortValues.count >= 5 else {
                throw TapCalibrationProfileError.insufficientSamples(
                    side: side,
                    force: .comfort
                )
            }
            guard firmValues.count >= 5 else {
                throw TapCalibrationProfileError.insufficientSamples(
                    side: side,
                    force: .firm
                )
            }
            guard comfortValues.allSatisfy(validFeature),
                  firmValues.allSatisfy(validFeature) else {
                throw TapCalibrationProfileError.invalidFeatures(
                    side: side,
                    force: comfortValues.allSatisfy(validFeature) ? .firm : .comfort
                )
            }
            guard comfortValues.filter({ $0.zImpulseMgS > 0 }).count * 5 >=
                    comfortValues.count * 4 else {
                throw TapCalibrationProfileError.inconsistentComfortDirection(
                    side: side
                )
            }

            allComfort.append(contentsOf: comfortValues)
            let firmPeaks = firmValues.map(\.peakG).sorted()
            let amplitudeCut = min(
                TapCalibration.mac14_2SpatialMultiTap
                    .firmTiers[.left]!.amplitudeCutG,
                max(0.08, percentile(firmPeaks, fraction: 0.10) * 0.90)
            )
            firmTiers[side] = TapCalibration.FirmTier(
                amplitudeCutG: amplitudeCut,
                lateralToPeakMaxMgSPerG:
                    TapCalibration.mac14_2SpatialMultiTap.firmTiers[.left]!
                        .lateralToPeakMaxMgSPerG,
                decayMaxMs:
                    TapCalibration.mac14_2SpatialMultiTap.firmTiers[.left]!
                        .decayMaxMs
            )
            summaries[side] = TapCalibrationSideSummary(
                comfortSampleCount: comfortValues.count,
                firmSampleCount: firmValues.count,
                comfortPeakMedianG: median(comfortValues.map(\.peakG)),
                firmPeakMedianG: median(firmValues.map(\.peakG)),
                zImpulseMedianMgS: median(comfortValues.map(\.zImpulseMgS))
            )
        }

        let weakestComfortPeak = allComfort.map(\.peakG).min() ??
            TapCalibration.mac14_2SpatialMultiTap.eventThresholdG
        var calibration = TapCalibration.mac14_2SpatialMultiTap
        calibration.version =
            "personal-spatial-\(UUID().uuidString.lowercased())"
        calibration.eventThresholdG = min(
            calibration.eventThresholdG,
            max(0.02, weakestComfortPeak * 0.55)
        )
        calibration.firmTiers = firmTiers

        return TapCalibrationProfile(
            calibration: calibration,
            sideSummaries: summaries
        )
    }

    private static func validFeature(_ feature: TapEventFeatures) -> Bool {
        feature.time.isFinite &&
            feature.peakG.isFinite && feature.peakG > 0 &&
            feature.decayMs.isFinite && feature.decayMs >= 0 &&
            feature.zImpulseMgS.isFinite &&
            feature.lateralImpulseMgS.isFinite &&
            feature.lateralImpulseMgS >= 0
    }

    private static func median(_ values: [Double]) -> Double {
        percentile(values.sorted(), fraction: 0.5)
    }

    private static func percentile(
        _ sorted: [Double],
        fraction: Double
    ) -> Double {
        guard let first = sorted.first else { return 0 }
        let index = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count - 1) * fraction).rounded()))
        )
        return sorted[index].isFinite ? sorted[index] : first
    }
}
