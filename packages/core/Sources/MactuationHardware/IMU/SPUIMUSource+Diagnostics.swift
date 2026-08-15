import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

extension SPUIMUSource {
    public var wakeRequired: Bool {
        statisticsLock.withLock { _wakeRequired }
    }

    public var wakePropertiesSet: [String] {
        statisticsLock.withLock { _wakePropertiesSet }
    }

    public var reportIntervalUsed: Int? {
        statisticsLock.withLock { _reportIntervalUsed }
    }

    public var totalReportCount: Int {
        statisticsLock.withLock { reportCounts.values.reduce(0, +) }
    }

    public func reportCount(for path: SensorPath) -> Int {
        statisticsLock.withLock { reportCounts[path, default: 0] }
    }

    public func effectiveRate(for path: SensorPath, elapsed: TimeInterval) -> Double {
        statisticsLock.withLock {
            let count = reportCounts[path, default: 0]
            if count > 1, let first = firstSampleTimes[path], let last = lastSampleTimes[path],
               last > first {
                return Double(count - 1) / (last - first)
            }
            guard elapsed > 0 else { return 0 }
            return Double(count) / elapsed
        }
    }

    public var malformedReport: String? {
        statisticsLock.withLock { malformedMessage }
    }

    public func firstReportLength(for path: SensorPath) -> Int? {
        statisticsLock.withLock { firstLengths[path] }
    }

    public func anomalies(for path: SensorPath) -> [String] {
        statisticsLock.withLock {
            var values: [String] = []
            let odd = oddLengthCounts[path, default: 0]
            let errors = callbackErrorCounts[path, default: 0]
            if odd > 0 {
                values.append("\(odd) reports differed from the first report length")
            }
            if errors > 0 {
                values.append("\(errors) callbacks returned non-success IOReturn")
            }
            if reportCounts[path, default: 0] == 0 {
                values.append("no input reports received")
            }
            return values
        }
    }

    func receive(channel: IMUChannel, result: IOReturn,
                 report: UnsafeMutablePointer<UInt8>, length: Int) {
        let path = channel.path
        if result != kIOReturnSuccess {
            let shouldReport = statisticsLock.withLock {
                callbackErrorCounts[path, default: 0] += 1
                return reportedCallbackFailures.insert(path).inserted
            }
            if shouldReport {
                emit(.failed(
                    path: path,
                    reason: "HID report callback failed with \(ioResult(result))"
                ))
            }
            return
        }

        var shouldReportMalformed = false
        statisticsLock.withLock {
            if firstLengths[path] == nil {
                firstLengths[path] = length
                let bytes = UnsafeBufferPointer(start: report, count: max(0, length))
                firstHex[path] = bytes.map { String(format: "%02x", $0) }.joined()
                if length < SPUIMUReportDecoder.minimumLength {
                    malformedMessage =
                        "\(path.rawValue) first report was \(length) bytes " +
                        "(<\(SPUIMUReportDecoder.minimumLength)); " +
                        "hex=\(firstHex[path] ?? "")"
                    shouldReportMalformed = true
                }
            } else if firstLengths[path] != length {
                oddLengthCounts[path, default: 0] += 1
            }
        }
        guard !shouldReportMalformed else {
            emit(.failed(path: path, reason: malformedReport ?? "malformed IMU report"))
            return
        }

        let bytes = UnsafeBufferPointer(start: report, count: max(0, length))
        guard let decoded = SPUIMUReportDecoder.decode(bytes) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime - startUptime
        statisticsLock.withLock {
            reportCounts[path, default: 0] += 1
            if firstSampleTimes[path] == nil { firstSampleTimes[path] = timestamp }
            lastSampleTimes[path] = timestamp
        }
        emit(.sample(.imu(
            path: path,
            sample: IMUSample(
                timestamp: timestamp,
                x: decoded.x,
                y: decoded.y,
                z: decoded.z
            )
        )))
    }

    func resetStatistics() {
        statisticsLock.withLock {
            reportCounts.removeAll()
            firstSampleTimes.removeAll()
            lastSampleTimes.removeAll()
            firstLengths.removeAll()
            firstHex.removeAll()
            oddLengthCounts.removeAll()
            callbackErrorCounts.removeAll()
            reportedCallbackFailures.removeAll()
            malformedMessage = nil
            _wakeRequired = false
            _wakePropertiesSet.removeAll()
            _reportIntervalUsed = nil
        }
    }
}
