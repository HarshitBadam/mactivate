import Foundation

/// A concrete sensor path the engine may acquire data from. Cases identify
/// *how* data is obtained, not just which physical sensor, because privilege
/// and rate differ per path (e.g. the two ALS strategies).
public enum SensorPath: String, Codable, CaseIterable, Sendable {
    case spuAccelerometer = "spu_accelerometer"
    case spuGyroscope = "spu_gyroscope"
    case spuAmbientLight = "spu_ambient_light"
    case displayServicesAmbientLight = "displayservices_ambient_light"
    case microphone = "microphone"
    case camera = "camera"
}

/// Timestamps are seconds on a monotonic clock. Which clock (hardware report
/// timestamp vs. host monotonic) is recorded per session in the manifest so
/// captures stay interpretable.
public typealias SensorTimestamp = Double

public struct IMUSample: Codable, Equatable, Sendable {
    public var timestamp: SensorTimestamp
    public var x: Double
    public var y: Double
    public var z: Double

    public init(timestamp: SensorTimestamp, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}

public struct ALSSample: Codable, Equatable, Sendable {
    public var timestamp: SensorTimestamp
    public var lux: Double
    /// Extra spectral channels where the path provides them (SPU ALS reports
    /// four); empty otherwise.
    public var channels: [Double]

    public init(timestamp: SensorTimestamp, lux: Double, channels: [Double] = []) {
        self.timestamp = timestamp
        self.lux = lux
        self.channels = channels
    }
}

public enum SensorSample: Equatable, Sendable {
    case imu(path: SensorPath, sample: IMUSample)
    case als(path: SensorPath, sample: ALSSample)

    public var path: SensorPath {
        switch self {
        case .imu(let path, _): return path
        case .als(let path, _): return path
        }
    }

    public var timestamp: SensorTimestamp {
        switch self {
        case .imu(_, let sample): return sample.timestamp
        case .als(_, let sample): return sample.timestamp
        }
    }
}
