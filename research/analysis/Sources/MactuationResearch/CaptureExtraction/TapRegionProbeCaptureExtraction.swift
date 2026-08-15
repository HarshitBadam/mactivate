import Foundation
import MactuationCapture
import MactuationCore

extension TapRegionProbeAnalyzer {
    public static func observations(
        from reader: CaptureReader
    ) throws -> [TapRegionProbeObservation] {
        let accelerometer = try imuSamples(
            reader: reader,
            path: .spuAccelerometer
        )
        let gyroscope = try imuSamples(
            reader: reader,
            path: .spuGyroscope
        )
        let labels = try reader.labels().filter {
            $0.label.hasPrefix("palm-")
        }
        guard !labels.isEmpty else {
            throw TapRegionProbeAnalysisError.missingLabels
        }

        return try labels.map { label in
            let side = try side(from: label.label)
            guard let intensity = TapRegionProbeIntensity(
                rawValue: label.intensity
            ) else {
                throw TapRegionProbeAnalysisError.invalidLabel(
                    "\(label.label)/\(label.intensity)"
                )
            }
            let accelBaseline = mean(
                accelerometer,
                from: max(0, label.start - 0.25),
                through: max(0, label.start - 0.02)
            )
            let expectedDetectedPeak = label.notes.hasPrefix("auto-detected")
                ? label.start + 0.15
                : nil
            let peakCandidates = accelerometer.filter {
                if let expectedDetectedPeak {
                    return abs($0.timestamp - expectedDetectedPeak) <= 0.04
                }
                return $0.timestamp >= label.start && $0.timestamp <= label.end
            }
            guard let peak = peakCandidates.max(by: {
                (vector($0) - accelBaseline).magnitude <
                    (vector($1) - accelBaseline).magnitude
            }) else {
                throw TapRegionProbeAnalysisError.noSamples(
                    label: label.label,
                    path: .spuAccelerometer
                )
            }
            guard gyroscope.contains(where: {
                abs($0.timestamp - peak.timestamp) <= 0.05
            }) else {
                throw TapRegionProbeAnalysisError.noSamples(
                    label: label.label,
                    path: .spuGyroscope
                )
            }

            let gyroBaseline = mean(
                gyroscope,
                from: max(0, peak.timestamp - 0.25),
                through: max(0, peak.timestamp - 0.08)
            )
            let accelDelta = vector(peak) - accelBaseline
            let accelImpulse = integral(
                accelerometer,
                center: peak.timestamp,
                halfWindow: 0.025,
                baseline: accelBaseline
            ) * 1000
            let gyro10 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.010,
                baseline: gyroBaseline
            )
            let gyro25 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.025,
                baseline: gyroBaseline
            )
            let gyro50 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroPeak = signedPeak(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroAtPeak = valueNearest(
                gyroscope,
                timestamp: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPre10 = integral(
                gyroscope,
                from: peak.timestamp - 0.010,
                through: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPost10 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.010,
                baseline: gyroBaseline
            )
            let gyroPre25 = integral(
                gyroscope,
                from: peak.timestamp - 0.025,
                through: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPost25 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.025,
                baseline: gyroBaseline
            )
            let gyroPost50 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.050,
                baseline: gyroBaseline
            )
            let gyroExtrema = extrema(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroEnergy = signedEnergyFractions(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline,
                signedBy: gyroPeak
            )
            let gyroDelay = signedExtremumDelays(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            var features: [String: Double] = [
                "accel_peak_g": accelDelta.magnitude,
                "accel_x_impulse_25_mg_s": accelImpulse.x,
                "accel_y_impulse_25_mg_s": accelImpulse.y,
                "accel_z_impulse_25_mg_s": accelImpulse.z,
                "label_start_to_peak_s": peak.timestamp - label.start
            ]
            let axes: [(String, (Vector3) -> Double)] = [
                ("x", { $0.x }),
                ("y", { $0.y }),
                ("z", { $0.z })
            ]
            for (axis, component) in axes {
                features["gyro_\(axis)_impulse_10_deg"] = component(gyro10)
                features["gyro_\(axis)_impulse_25_deg"] = component(gyro25)
                features["gyro_\(axis)_impulse_50_deg"] = component(gyro50)
                features["gyro_\(axis)_peak_deg_s"] = component(gyroPeak)
                features["gyro_\(axis)_at_accel_peak_deg_s"] =
                    component(gyroAtPeak)
                features["gyro_\(axis)_pre_impulse_10_deg"] =
                    component(gyroPre10)
                features["gyro_\(axis)_post_impulse_10_deg"] =
                    component(gyroPost10)
                features["gyro_\(axis)_post_impulse_25_deg"] =
                    component(gyroPost25)
                features["gyro_\(axis)_post_impulse_50_deg"] =
                    component(gyroPost50)
                features["gyro_\(axis)_peak_balance_deg_s"] =
                    component(gyroExtrema.maximum) +
                    component(gyroExtrema.minimum)
                features["gyro_\(axis)_post_pre_delta_25_deg"] =
                    component(gyroPost25) - component(gyroPre25)
                features["gyro_\(axis)_signed_energy_fraction_50"] =
                    component(gyroEnergy)
                features["gyro_\(axis)_signed_extremum_delay_ms"] =
                    component(gyroDelay)
            }
            return TapRegionProbeObservation(
                side: side,
                intensity: intensity,
                repetition: label.repetition,
                peakTimestamp: peak.timestamp,
                features: features
            )
        }
    }

    private static func imuSamples(
        reader: CaptureReader,
        path: SensorPath
    ) throws -> [IMUSample] {
        let values: [IMUSample] = try reader.samples(for: path).compactMap {
            guard case .imu(_, let sample) = $0 else { return nil }
            return sample
        }
        guard !values.isEmpty else {
            throw TapRegionProbeAnalysisError.missingSensor(path)
        }
        return values
    }

    private static func side(from label: String) throws -> TapRegionProbeSide {
        switch label {
        case "palm-left": return .left
        case "palm-right": return .right
        default: throw TapRegionProbeAnalysisError.invalidLabel(label)
        }
    }
}
