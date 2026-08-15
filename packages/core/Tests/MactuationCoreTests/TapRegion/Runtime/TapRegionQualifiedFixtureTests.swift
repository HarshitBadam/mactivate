import Foundation
import XCTest
@testable import MactuationCore

final class TapRegionQualifiedFixtureTests: XCTestCase {
    func testQualifiedFixtureTransfersFortyOfFortyWithFrozenMedianModel()
        throws {
        let rows = try featureFixtureRows()
        let grouped = Dictionary(grouping: rows) {
            GestureKey(
                session: $0.session,
                side: $0.side,
                pattern: $0.pattern,
                repetition: $0.repetition
            )
        }
        func gesture(
            key: GestureKey,
            members: [FeatureFixtureRow]
        ) -> TapRegionCalibrationGesture {
            TapRegionCalibrationGesture(
                side: key.side,
                pattern: key.pattern,
                repetition: key.repetition,
                memberFeatures: members.sorted {
                    $0.member < $1.member
                }.map(\.feature)
            )
        }
        let training = grouped.compactMap { key, members in
            key.session == "training"
                ? gesture(key: key, members: members)
                : nil
        }
        let result = try TapRegionCalibrationProfileBuilder.build(
            gestures: training,
            version: "personal-region-qualified-fixture"
        )
        let validation = grouped.compactMap { key, members in
            key.session == "validation"
                ? gesture(key: key, members: members)
                : nil
        }
        let correct = validation.filter {
            result.profile.predict(feature: $0.medianFeature!) ==
                TapRegionPrediction(side: $0.side)
        }.count

        XCTAssertEqual(validation.count, 40)
        XCTAssertEqual(correct, 40)
    }

    func testProductionExtractorMatchesQualifiedDualIMUFixture() throws {
        let expected = Dictionary(
            uniqueKeysWithValues: try featureFixtureRows().map {
                (MemberKey(
                    session: $0.session,
                    side: $0.side,
                    pattern: $0.pattern,
                    repetition: $0.repetition,
                    member: $0.member
                ), $0.feature)
            }
        )
        let groups = Dictionary(grouping: try dualIMUFixtureRows()) {
            $0.key
        }

        XCTAssertEqual(groups.count, 20)
        for (key, rows) in groups {
            let first = try XCTUnwrap(rows.first)
            let feature = try TapRegionFeatureExtractor().extract(
                gyroscope: rows.map(\.gyro),
                peakTimestamp: first.peakTimestamp
            )
            XCTAssertEqual(
                feature.gyroXPeakBalanceDegS,
                try XCTUnwrap(expected[key]),
                accuracy: 1e-9
            )
        }
    }

    private func featureFixtureRows() throws -> [FeatureFixtureRow] {
        try fixtureRows(named: "region_multitap_features").map {
            guard $0.count == 7,
                  let side = TapRegionSide(rawValue: String($0[1])),
                  let pattern = TapRegionPattern(rawValue: String($0[2])),
                  let repetition = Int($0[3]),
                  let member = Int($0[4]),
                  let feature = Double($0[6]) else {
                throw FixtureError.invalidRow
            }
            return FeatureFixtureRow(
                session: String($0[0]),
                side: side,
                pattern: pattern,
                repetition: repetition,
                member: member,
                feature: feature
            )
        }
    }

    private func dualIMUFixtureRows() throws -> [DualIMUFixtureRow] {
        try fixtureRows(named: "region_multitap_dual_imu").map {
            guard $0.count == 13,
                  let side = TapRegionSide(rawValue: String($0[1])),
                  let pattern = TapRegionPattern(rawValue: String($0[2])),
                  let repetition = Int($0[3]),
                  let member = Int($0[4]),
                  let peak = Double($0[5]),
                  let timestamp = Double($0[6]),
                  let x = Double($0[10]),
                  let y = Double($0[11]),
                  let z = Double($0[12]) else {
                throw FixtureError.invalidRow
            }
            return DualIMUFixtureRow(
                key: MemberKey(
                    session: String($0[0]),
                    side: side,
                    pattern: pattern,
                    repetition: repetition,
                    member: member
                ),
                peakTimestamp: peak,
                gyro: IMUSample(timestamp: timestamp, x: x, y: y, z: z)
            )
        }
    }

    private func fixtureRows(named name: String) throws -> [[Substring]] {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "csv"
        ) else {
            throw FixtureError.missing
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { $0.split(separator: ",", omittingEmptySubsequences: false) }
    }
}

private struct GestureKey: Hashable {
    var session: String
    var side: TapRegionSide
    var pattern: TapRegionPattern
    var repetition: Int
}

private struct MemberKey: Hashable {
    var session: String
    var side: TapRegionSide
    var pattern: TapRegionPattern
    var repetition: Int
    var member: Int
}

private struct FeatureFixtureRow {
    var session: String
    var side: TapRegionSide
    var pattern: TapRegionPattern
    var repetition: Int
    var member: Int
    var feature: Double
}

private struct DualIMUFixtureRow {
    var key: MemberKey
    var peakTimestamp: SensorTimestamp
    var gyro: IMUSample
}

private enum FixtureError: Error {
    case missing
    case invalidRow
}
