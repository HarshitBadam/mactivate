import Foundation
import MactuationCore

/// Not thread-safe; feed it from a single serial queue (sources already
/// deliver per-path in timestamp order).
public final class CaptureWriter {
    public let directory: URL

    private var manifest: SessionManifest
    private var streams: [SensorPath: FileHandle] = [:]
    private var labels: [LabelSpan] = []
    private var finished = false

    public init(directory: URL, manifest: SessionManifest) throws {
        self.directory = directory
        self.manifest = manifest
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Creates the conventional `captures/<yyyymmdd-hhmmss>-<label>/` directory.
    public static func conventionalDirectory(under root: URL, label: String, startedAt: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return root.appendingPathComponent("\(formatter.string(from: startedAt))-\(label)")
    }

    public func append(_ sample: SensorSample) throws {
        precondition(!finished, "capture already finalized")
        let handle = try stream(for: sample.path)
        try handle.write(contentsOf: Data((CaptureFormat.csvLine(for: sample) + "\n").utf8))
    }

    public func addLabel(_ span: LabelSpan) {
        precondition(!finished, "capture already finalized")
        labels.append(span)
    }

    public func recordSensorMetadata(path: SensorPath, effectiveRateHz: Double? = nil,
                                     acquisitionParameters: [String: String] = [:],
                                     anomalies: [String] = []) {
        guard let index = manifest.sensors.firstIndex(where: { $0.path == path }) else {
            manifest.sensors.append(SessionManifest.SensorRecord(
                path: path, file: CaptureFormat.streamFileName(for: path),
                effectiveRateHz: effectiveRateHz,
                acquisitionParameters: acquisitionParameters, anomalies: anomalies))
            return
        }
        manifest.sensors[index].effectiveRateHz = effectiveRateHz ?? manifest.sensors[index].effectiveRateHz
        manifest.sensors[index].acquisitionParameters.merge(acquisitionParameters) { _, new in new }
        manifest.sensors[index].anomalies.append(contentsOf: anomalies)
    }

    public func finalize() throws {
        precondition(!finished, "capture already finalized")
        finished = true
        for handle in streams.values {
            try handle.close()
        }
        streams.removeAll()
        for record in manifest.sensors {
            let url = directory.appendingPathComponent(record.file)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
        }

        let labelLines = [CaptureFormat.labelsHeader] + labels.map(CaptureFormat.csvLine(for:))
        try Data((labelLines.joined(separator: "\n") + "\n").utf8)
            .write(to: directory.appendingPathComponent(CaptureFormat.labelsFileName))

        let manifestData = try CaptureFormat.manifestEncoder().encode(manifest)
        try manifestData.write(to: directory.appendingPathComponent(CaptureFormat.manifestFileName))
    }

    private func stream(for path: SensorPath) throws -> FileHandle {
        if let handle = streams[path] { return handle }
        let url = directory.appendingPathComponent(CaptureFormat.streamFileName(for: path))
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        streams[path] = handle
        if !manifest.sensors.contains(where: { $0.path == path }) {
            manifest.sensors.append(SessionManifest.SensorRecord(
                path: path, file: CaptureFormat.streamFileName(for: path)))
        }
        return handle
    }
}
