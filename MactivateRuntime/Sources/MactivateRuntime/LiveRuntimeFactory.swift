import MactuationCore
import MactuationHardware

public protocol RuntimeSourceCreating {
    func makeTapSource() throws -> any SensorSource
    func makePanelHintSource() throws -> any SensorSource
}

public struct LiveRuntimeFactory: RuntimeSourceCreating {
    public let imuReportIntervalMicroseconds: Int
    public let alsReportIntervalMicroseconds: Int
    public let alsPollHz: Double
    public let includeGyroscope: Bool

    public init(imuReportIntervalMicroseconds: Int = 1_250,
                alsReportIntervalMicroseconds: Int = 50_000,
                alsPollHz: Double = 20,
                includeGyroscope: Bool = true) {
        self.imuReportIntervalMicroseconds = imuReportIntervalMicroseconds
        self.alsReportIntervalMicroseconds = alsReportIntervalMicroseconds
        self.alsPollHz = alsPollHz
        self.includeGyroscope = includeGyroscope
    }

    public func makeTapSource() throws -> any SensorSource {
        try SPUIMUSource(
            includeGyroscope: includeGyroscope,
            allowMissingGyroscope: true,
            startupReportInterval: imuReportIntervalMicroseconds
        )
    }

    public func makePanelHintSource() throws -> any SensorSource {
        try RegistryALSSource(
            pollHz: alsPollHz,
            reportIntervalOverride: alsReportIntervalMicroseconds
        )
    }
}
