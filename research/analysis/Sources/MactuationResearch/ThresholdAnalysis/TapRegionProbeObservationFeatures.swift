import Foundation
import MactuationCore

/// Research-only: production calibration (`TapRegionCalibrationBuilder`)
/// fits a single feature it already knows, so it never needs this list.
public extension TapRegionProbeObservation {
    static let modelFeatureNames: [String] = {
        var names = [
            "accel_peak_g",
            "accel_x_impulse_25_mg_s",
            "accel_y_impulse_25_mg_s",
            "accel_z_impulse_25_mg_s"
        ]
        for axis in ["x", "y", "z"] {
            names += [
                "gyro_\(axis)_impulse_10_deg",
                "gyro_\(axis)_impulse_25_deg",
                "gyro_\(axis)_impulse_50_deg",
                "gyro_\(axis)_peak_deg_s",
                "gyro_\(axis)_at_accel_peak_deg_s",
                "gyro_\(axis)_pre_impulse_10_deg",
                "gyro_\(axis)_post_impulse_10_deg",
                "gyro_\(axis)_post_impulse_25_deg",
                "gyro_\(axis)_post_impulse_50_deg",
                "gyro_\(axis)_peak_balance_deg_s",
                "gyro_\(axis)_post_pre_delta_25_deg",
                "gyro_\(axis)_signed_energy_fraction_50",
                "gyro_\(axis)_signed_extremum_delay_ms"
            ]
        }
        return names
    }()
}
