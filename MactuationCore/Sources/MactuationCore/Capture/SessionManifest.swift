import Foundation

/// `session.json` — everything needed to interpret and reproduce a capture.
public struct SessionManifest: Codable, Equatable, Sendable {
    public struct Environment: Codable, Equatable, Sendable {
        public struct HIDUsage: Codable, Equatable, Sendable {
            public var usagePage: UInt32
            public var usage: UInt32

            public init(usagePage: UInt32, usage: UInt32) {
                self.usagePage = usagePage
                self.usage = usage
            }
        }

        public enum Compatibility: String, Codable, Sendable {
            case unknown
            case supported
            case unsupported
            case inconclusive
        }

        public var modelIdentifier: String
        public var chip: String
        public var osVersion: String
        public var osBuild: String
        public var notchPresent: Bool?
        public var requiredPrivileges: [String]
        public var discoveredHIDUsages: [HIDUsage]
        public var compatibility: Compatibility

        public init(modelIdentifier: String = "unknown", chip: String = "unknown",
                    osVersion: String = "unknown", osBuild: String = "unknown",
                    notchPresent: Bool? = nil, requiredPrivileges: [String] = [],
                    discoveredHIDUsages: [HIDUsage] = [],
                    compatibility: Compatibility = .unknown) {
            self.modelIdentifier = modelIdentifier
            self.chip = chip
            self.osVersion = osVersion
            self.osBuild = osBuild
            self.notchPresent = notchPresent
            self.requiredPrivileges = requiredPrivileges
            self.discoveredHIDUsages = discoveredHIDUsages
            self.compatibility = compatibility
        }
    }

    public struct SensorRecord: Codable, Equatable, Sendable {
        public var path: SensorPath
        public var file: String
        public var effectiveRateHz: Double?
        /// Wake/report parameters used, e.g. ReportInterval — kept as strings
        /// because the values are hardware-reported and unvalidated.
        public var acquisitionParameters: [String: String]
        public var anomalies: [String]

        public init(path: SensorPath, file: String, effectiveRateHz: Double? = nil,
                    acquisitionParameters: [String: String] = [:], anomalies: [String] = []) {
            self.path = path
            self.file = file
            self.effectiveRateHz = effectiveRateHz
            self.acquisitionParameters = acquisitionParameters
            self.anomalies = anomalies
        }
    }

    public var formatVersion: Int
    public var label: String
    public var startedAt: Date
    public var clock: String
    public var toolVersion: String
    public var environment: Environment
    public var sensors: [SensorRecord]
    public var notes: String

    public static let currentFormatVersion = 1

    public init(label: String, startedAt: Date, clock: String = "host_monotonic",
                toolVersion: String, environment: Environment = Environment(),
                sensors: [SensorRecord] = [], notes: String = "") {
        self.formatVersion = Self.currentFormatVersion
        self.label = label
        self.startedAt = startedAt
        self.clock = clock
        self.toolVersion = toolVersion
        self.environment = environment
        self.sensors = sensors
        self.notes = notes
    }
}

/// One row of the `labels.csv` sidecar.
public struct LabelSpan: Equatable, Sendable {
    public var start: SensorTimestamp
    public var end: SensorTimestamp
    public var label: String
    public var repetition: Int
    public var intensity: String
    public var notes: String

    public init(start: SensorTimestamp, end: SensorTimestamp, label: String,
                repetition: Int = 0, intensity: String = "", notes: String = "") {
        self.start = start
        self.end = end
        self.label = label
        self.repetition = repetition
        self.intensity = intensity
        self.notes = notes
    }
}
