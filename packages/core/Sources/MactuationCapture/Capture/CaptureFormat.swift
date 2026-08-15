import Foundation
import MactuationCore

/// Canonical on-disk encoding of the capture session directory:
///
///     <session>/session.json      manifest
///     <session>/labels.csv        label spans
///     <session>/<path>.csv        one raw stream per sensor path
///
/// IMU rows: `timestamp_s,x,y,z` · ALS rows: `timestamp_s,lux[,ch...]`.
/// Numbers are emitted with a locale-independent, round-trippable format so
/// replay of a written capture is exact.
public enum CaptureFormat {
    public static let manifestFileName = "session.json"
    public static let labelsFileName = "labels.csv"
    public static let labelsHeader = "t_start_s,t_end_s,label,repetition,intensity,notes"

    public static func streamFileName(for path: SensorPath) -> String {
        "\(path.rawValue).csv"
    }

    public static func encode(_ value: Double) -> String {
        // %.17g round-trips every Double and never uses locale separators.
        String(format: "%.17g", value)
    }

    public static func csvLine(for sample: SensorSample) -> String {
        switch sample {
        case .imu(_, let s):
            return [encode(s.timestamp), encode(s.x), encode(s.y), encode(s.z)].joined(separator: ",")
        case .als(_, let s):
            return ([encode(s.timestamp), encode(s.lux)] + s.channels.map(encode)).joined(separator: ",")
        }
    }

    static func parseSample(line: String, path: SensorPath) throws -> SensorSample {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func number(_ index: Int) throws -> Double {
            guard index < fields.count, let value = Double(fields[index]) else {
                throw SensorSourceError.captureUnreadable("bad field \(index) in line: \(line)")
            }
            return value
        }
        switch path {
        case .spuAccelerometer, .spuGyroscope:
            return .imu(path: path, sample: IMUSample(timestamp: try number(0), x: try number(1),
                                                      y: try number(2), z: try number(3)))
        case .spuAmbientLight, .displayServicesAmbientLight:
            let channels = try (2..<fields.count).map { try number($0) }
            return .als(path: path, sample: ALSSample(timestamp: try number(0), lux: try number(1),
                                                      channels: channels))
        case .microphone, .camera:
            throw SensorSourceError.captureUnreadable("\(path.rawValue) captures are stored as media, not CSV")
        }
    }

    static func csvLine(for span: LabelSpan) -> String {
        [encode(span.start), encode(span.end), escapeCSV(span.label), String(span.repetition),
         escapeCSV(span.intensity), escapeCSV(span.notes)].joined(separator: ",")
    }

    static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func manifestEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func manifestDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
