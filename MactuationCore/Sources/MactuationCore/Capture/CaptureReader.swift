import Foundation

/// Reads a capture session directory written by `CaptureWriter` (or by the
/// future probe tool, which shares the format).
public struct CaptureReader {
    public let directory: URL
    public let manifest: SessionManifest

    public init(directory: URL) throws {
        self.directory = directory
        let manifestURL = directory.appendingPathComponent(CaptureFormat.manifestFileName)
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            throw SensorSourceError.captureUnreadable("missing \(CaptureFormat.manifestFileName)")
        }
        self.manifest = try CaptureFormat.manifestDecoder().decode(SessionManifest.self, from: data)
        guard manifest.formatVersion == SessionManifest.currentFormatVersion else {
            throw SensorSourceError.captureUnreadable("unsupported format version \(manifest.formatVersion)")
        }
    }

    public func samples(for path: SensorPath) throws -> [SensorSample] {
        guard let record = manifest.sensors.first(where: { $0.path == path }) else { return [] }
        let url = directory.appendingPathComponent(record.file)
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else {
            throw SensorSourceError.captureUnreadable("missing stream file \(record.file)")
        }
        return try text.split(separator: "\n").map {
            try CaptureFormat.parseSample(line: String($0), path: path)
        }
    }

    /// All samples across paths, merged into one non-decreasing timeline.
    /// Ties order by path name so the merge itself is deterministic.
    public func mergedSamples() throws -> [SensorSample] {
        var all: [SensorSample] = []
        for record in manifest.sensors {
            all.append(contentsOf: try samples(for: record.path))
        }
        return all.enumerated().sorted {
            ($0.element.timestamp, $0.element.path.rawValue, $0.offset) <
                ($1.element.timestamp, $1.element.path.rawValue, $1.offset)
        }.map(\.element)
    }

    public func labels() throws -> [LabelSpan] {
        let url = directory.appendingPathComponent(CaptureFormat.labelsFileName)
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else {
            throw SensorSourceError.captureUnreadable("missing \(CaptureFormat.labelsFileName)")
        }
        var records = try parseCSVRecords(text)
        guard !records.isEmpty else { return [] }
        records.removeFirst() // header
        return try records.map { fields in
            guard fields.count >= 6, let start = Double(fields[0]), let end = Double(fields[1]),
                  let repetition = Int(fields[3]) else {
                throw SensorSourceError.captureUnreadable("bad label row: \(fields.joined(separator: ","))")
            }
            return LabelSpan(start: start, end: end, label: fields[2], repetition: repetition,
                             intensity: fields[4], notes: fields[5])
        }
    }

    private func parseCSVRecords(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        current.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" && current.isEmpty {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else if character == "\n" {
                fields.append(current)
                records.append(fields)
                fields = []
                current = ""
            } else if character == "\r" {
                // Ignore CR in CRLF record separators.
            } else {
                current.append(character)
            }
            index = text.index(after: index)
        }
        guard !inQuotes else {
            throw SensorSourceError.captureUnreadable("unterminated quoted label field")
        }
        if !fields.isEmpty || !current.isEmpty {
            fields.append(current)
            records.append(fields)
        }
        return records
    }
}
