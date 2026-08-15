import Foundation
import MactuationCore

extension TapRegionProbeAnalyzer {
    struct Vector3 {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Vector3(x: 0, y: 0, z: 0)

        static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
            Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
            Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
        }

        static func * (lhs: Vector3, rhs: Double) -> Vector3 {
            Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
        }

        var magnitude: Double {
            (x * x + y * y + z * z).squareRoot()
        }
    }

    static func vector(_ sample: IMUSample) -> Vector3 {
        Vector3(x: sample.x, y: sample.y, z: sample.z)
    }

    static func mean(
        _ samples: [IMUSample],
        from start: SensorTimestamp,
        through end: SensorTimestamp
    ) -> Vector3 {
        let selected = samples.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
        guard !selected.isEmpty else { return .zero }
        let sum = selected.reduce(Vector3.zero) {
            $0 + vector($1)
        }
        return sum * (1 / Double(selected.count))
    }

    static func integral(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        integral(
            samples,
            from: center - halfWindow,
            through: center + halfWindow,
            baseline: baseline
        )
    }

    static func integral(
        _ samples: [IMUSample],
        from start: SensorTimestamp,
        through end: SensorTimestamp,
        baseline: Vector3
    ) -> Vector3 {
        let selected = samples.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
        guard selected.count >= 2 else { return .zero }
        var result = Vector3.zero
        for (previous, current) in zip(selected, selected.dropFirst()) {
            let dt = current.timestamp - previous.timestamp
            guard dt > 0 else { continue }
            let previousValue = vector(previous) - baseline
            let currentValue = vector(current) - baseline
            result = result + (previousValue + currentValue) * (dt / 2)
        }
        return result
    }

    static func valueNearest(
        _ samples: [IMUSample],
        timestamp: SensorTimestamp,
        baseline: Vector3
    ) -> Vector3 {
        guard let sample = samples.min(by: {
            abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
        }) else {
            return .zero
        }
        return vector(sample) - baseline
    }

    static func extrema(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> (minimum: Vector3, maximum: Vector3) {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        return (
            minimum: Vector3(
                x: values.map(\.x).min() ?? 0,
                y: values.map(\.y).min() ?? 0,
                z: values.map(\.z).min() ?? 0
            ),
            maximum: Vector3(
                x: values.map(\.x).max() ?? 0,
                y: values.map(\.y).max() ?? 0,
                z: values.map(\.z).max() ?? 0
            )
        )
    }

    static func signedEnergyFractions(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3,
        signedBy peak: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        let xEnergy = values.reduce(0) { $0 + $1.x * $1.x }
        let yEnergy = values.reduce(0) { $0 + $1.y * $1.y }
        let zEnergy = values.reduce(0) { $0 + $1.z * $1.z }
        let total = xEnergy + yEnergy + zEnergy
        guard total > 0 else { return .zero }
        return Vector3(
            x: copysign(xEnergy / total, peak.x),
            y: copysign(yEnergy / total, peak.y),
            z: copysign(zEnergy / total, peak.z)
        )
    }

    static func signedExtremumDelays(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }
        func delay(_ component: (Vector3) -> Double) -> Double {
            guard let sample = values.max(by: {
                abs(component(vector($0) - baseline)) <
                    abs(component(vector($1) - baseline))
            }) else {
                return 0
            }
            let value = component(vector(sample) - baseline)
            return (sample.timestamp - center) * 1_000 *
                (value < 0 ? -1 : 1)
        }
        return Vector3(
            x: delay { $0.x },
            y: delay { $0.y },
            z: delay { $0.z }
        )
    }

    static func signedPeak(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        return Vector3(
            x: values.max(by: { abs($0.x) < abs($1.x) })?.x ?? 0,
            y: values.max(by: { abs($0.y) < abs($1.y) })?.y ?? 0,
            z: values.max(by: { abs($0.z) < abs($1.z) })?.z ?? 0
        )
    }
}
