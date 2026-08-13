import Foundation
import XCTest
@testable import MactuationCore

final class CommittedFixtureTests: XCTestCase {
    func testComfortableTapFixturePassesBatchAndLivePaths() throws {
        let samples = try loadIMU("imu_comfortable_tap")
        let rate = try effectiveRate(samples)
        let batch = TapClassifier(calibration: .mac14_2Discovery).classify(
            imuSamples: samples,
            sampleRateHz: rate
        )
        XCTAssertEqual(batch.filter(\.verdict.isAccepted).count, 1)
        XCTAssertEqual(batch.first?.verdict, .acceptedComfort)

        let stream = try TapStreamClassifier(sampleRateHz: rate)
        var streamed: [TapGroup] = []
        for sample in samples {
            streamed.append(contentsOf: try stream.append(sample))
        }
        streamed.append(contentsOf: stream.finishForReplay())

        XCTAssertEqual(streamed.map(\.verdict), batch.map(\.verdict))
        XCTAssertEqual(
            streamed.filter(\.verdict.isAccepted).map {
                $0.eventID(calibrationVersion: stream.classifier.calibration.version)
            },
            batch.filter(\.verdict.isAccepted).map {
                $0.eventID(calibrationVersion: stream.classifier.calibration.version)
            }
        )
    }

    func testTypingFixtureContainsCandidatesButNoAcceptedTap() throws {
        let samples = try loadIMU("imu_typing_baseline")
        let groups = TapClassifier(calibration: .mac14_2Discovery).classify(
            imuSamples: samples,
            sampleRateHz: try effectiveRate(samples)
        )

        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(groups.allSatisfy { !$0.verdict.isAccepted })
    }

    func testBrightAndDimALSFixturesExerciseReadinessAndHint() throws {
        let bright = try replayALS("als_bright_hand_approach")
        XCTAssertTrue(bright.contains(.readinessChanged(.available)))
        XCTAssertEqual(
            bright.filter {
                if case .panelOpenHint = $0 { return true }
                return false
            }.count,
            1
        )

        let dim = try replayALS("als_dim_floor")
        XCTAssertEqual(dim, [.readinessChanged(.tooDim)])
    }

    func testStationaryShadowFixtureDocumentsKnownFalsePositive() throws {
        let events = try replayALS("als_stationary_shadow")

        XCTAssertTrue(events.contains {
            if case .panelOpenHint = $0 { return true }
            return false
        })
    }

    private func replayALS(_ name: String) throws -> [AmbientLightDipEvent] {
        let detector = try AmbientLightDipDetector()
        return try loadALS(name).flatMap { try detector.process($0) }
    }

    private func loadIMU(_ name: String) throws -> [IMUSample] {
        try rows(in: name).map { columns in
            guard columns.count == 4,
                  let timestamp = Double(columns[0]),
                  let x = Double(columns[1]),
                  let y = Double(columns[2]),
                  let z = Double(columns[3]) else {
                throw FixtureError.invalidRow(name)
            }
            return IMUSample(timestamp: timestamp, x: x, y: y, z: z)
        }
    }

    private func loadALS(_ name: String) throws -> [ALSSample] {
        try rows(in: name).map { columns in
            guard columns.count == 2,
                  let timestamp = Double(columns[0]),
                  let lux = Double(columns[1]) else {
                throw FixtureError.invalidRow(name)
            }
            return ALSSample(timestamp: timestamp, lux: lux)
        }
    }

    private func rows(in name: String) throws -> [[Substring]] {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "csv"
        ) else {
            throw FixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { $0.split(separator: ",", omittingEmptySubsequences: false) }
    }

    private func effectiveRate(_ samples: [IMUSample]) throws -> Double {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last,
              last.timestamp > first.timestamp else {
            throw FixtureError.invalidRow("effective rate")
        }
        return Double(samples.count - 1) / (last.timestamp - first.timestamp)
    }
}

private enum FixtureError: Error {
    case missing(String)
    case invalidRow(String)
}
