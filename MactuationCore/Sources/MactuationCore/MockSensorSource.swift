import Foundation

/// Deterministic synthetic sensor streams for tests and offline development.
///
/// Never a capability claim: mock data exercises plumbing (capture, replay,
/// digests, future detectors) but says nothing about real hardware. Signal
/// shapes follow the expected signatures in the gesture-hypotheses doc so
/// downstream code sees plausible structure, not white noise.
public final class MockSensorSource: SensorSource {
    public struct Configuration: Sendable {
        public var seed: UInt64
        public var duration: Double
        public var imuRateHz: Double
        public var alsRateHz: Double
        public var noiseAmplitudeG: Double
        public var baselineLux: Double
        /// (time, peak amplitude in g) of injected tap-like transients.
        public var taps: [(time: Double, amplitude: Double)]
        /// (start, end) spans where the ALS is shadowed, hand-cover-like.
        public var covers: [(start: Double, end: Double)]

        public init(seed: UInt64 = 1, duration: Double = 10, imuRateHz: Double = 100,
                    alsRateHz: Double = 10, noiseAmplitudeG: Double = 0.001,
                    baselineLux: Double = 300,
                    taps: [(time: Double, amplitude: Double)] = [],
                    covers: [(start: Double, end: Double)] = []) {
            self.seed = seed
            self.duration = duration
            self.imuRateHz = imuRateHz
            self.alsRateHz = alsRateHz
            self.noiseAmplitudeG = noiseAmplitudeG
            self.baselineLux = baselineLux
            self.taps = taps
            self.covers = covers
        }
    }

    public let paths: [SensorPath] = [.spuAccelerometer, .spuAmbientLight]

    private let configuration: Configuration
    private var started = false

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func start(handler: @escaping (SensorSample) -> Void) throws {
        guard !started else { throw SensorSourceError.alreadyStarted }
        started = true
        for sample in generate() {
            handler(sample)
        }
    }

    public func stop() {
        started = false
    }

    public func generate() -> [SensorSample] {
        var random = SplitMix64(seed: configuration.seed)
        var samples: [SensorSample] = []

        let imuCount = Int(configuration.duration * configuration.imuRateHz)
        for index in 0..<imuCount {
            let t = Double(index) / configuration.imuRateHz
            var z = 1.0 + configuration.noiseAmplitudeG * random.nextSymmetric()
            for tap in configuration.taps {
                let dt = t - tap.time
                // Sharp onset, ~30 ms exponential decay — H-TAP-PALM's expected shape.
                if dt >= 0 && dt < 0.1 {
                    z += tap.amplitude * exp(-dt / 0.03)
                }
            }
            let x = configuration.noiseAmplitudeG * random.nextSymmetric()
            let y = configuration.noiseAmplitudeG * random.nextSymmetric()
            samples.append(.imu(path: .spuAccelerometer,
                                sample: IMUSample(timestamp: t, x: x, y: y, z: z)))
        }

        let alsCount = Int(configuration.duration * configuration.alsRateHz)
        for index in 0..<alsCount {
            let t = Double(index) / configuration.alsRateHz
            var lux = configuration.baselineLux * (1.0 + 0.01 * random.nextSymmetric())
            for cover in configuration.covers where t >= cover.start && t <= cover.end {
                lux *= 0.1
            }
            samples.append(.als(path: .spuAmbientLight,
                                sample: ALSSample(timestamp: t, lux: lux)))
        }

        return samples.sorted {
            ($0.timestamp, $0.path.rawValue) < ($1.timestamp, $1.path.rawValue)
        }
    }
}

/// Seeded PRNG with stable output across platforms and Swift versions,
/// which `SystemRandomNumberGenerator` does not guarantee.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// Uniform in [-1, 1].
    mutating func nextSymmetric() -> Double {
        Double(next() >> 11) / Double(1 << 53) * 2 - 1
    }
}
