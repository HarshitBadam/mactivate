import Foundation
import MactuationCore

let dualIMUPaths: [SensorPath] = [
    .spuAccelerometer,
    .spuGyroscope
]

let runtimeIMURate = 800.0

func sendIMU(
    to source: ScriptedSensorSource,
    startTime: Double = 0,
    duration: Double,
    pulses: [(Double, Double, Double, Double)],
    gyroSide: TapRegionSide? = .left
) {
    let firstIndex = Int(startTime * runtimeIMURate)
    let endIndex = Int((startTime + duration) * runtimeIMURate)
    for index in firstIndex..<endIndex {
        let time = Double(index) / runtimeIMURate
        var x = 0.02
        var y = -0.01
        var z = -1.0
        for pulse in pulses {
            let delta = time - pulse.0
            if delta >= 0, delta < 0.025 {
                let decay = exp(-delta / 0.005)
                x += pulse.1 * decay
                y += pulse.2 * decay
                z += pulse.3 * decay
            }
        }
        var gyroX = 0.0
        for pulse in pulses {
            let delta = time - pulse.0
            if delta >= -0.02, delta < 0 {
                switch gyroSide {
                case .left: gyroX = -4
                case .right: gyroX = -1
                case nil: gyroX = -1
                }
            } else if delta >= 0, delta <= 0.02 {
                switch gyroSide {
                case .left: gyroX = 1
                case .right: gyroX = 4
                case nil: gyroX = 1
                }
            }
        }
        if source.paths.contains(.spuGyroscope) {
            source.send(.sample(.imu(
                path: .spuGyroscope,
                sample: IMUSample(
                    timestamp: time,
                    x: gyroX,
                    y: 0,
                    z: 0
                )
            )))
        }
        source.send(.sample(.imu(
            path: .spuAccelerometer,
            sample: IMUSample(timestamp: time, x: x, y: y, z: z)
        )))
    }
}

func sendLux(_ values: [Double],
             to source: ScriptedSensorSource) {
    for (index, lux) in values.enumerated() {
        source.send(.sample(.als(
            path: .spuAmbientLight,
            sample: ALSSample(timestamp: Double(index) * 0.1, lux: lux)
        )))
    }
}
