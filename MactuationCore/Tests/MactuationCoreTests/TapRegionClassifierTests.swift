import Foundation
import XCTest
@testable import MactuationCore

final class TapRegionClassifierTests: XCTestCase {
    func testFeatureExtractorComputesBaselineCorrectedPeakBalance() throws {
        let samples = stride(from: 0.70, through: 1.10, by: 0.00125).map {
            time -> IMUSample in
            let x: Double
            if time >= 0.98 && time < 1.0 {
                x = -4
            } else if time >= 1.0 && time <= 1.02 {
                x = 1
            } else {
                x = 0
            }
            return IMUSample(timestamp: time, x: x, y: 0, z: 0)
        }

        let feature = try TapRegionFeatureExtractor().extract(
            gyroscope: samples,
            peakTimestamp: 1.0
        )

        XCTAssertEqual(feature.gyroXPeakBalanceDegS, -3, accuracy: 1e-9)
    }

    func testProfileUsesGuardBandAndFailsClosedWhenInvalid() {
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )

        XCTAssertEqual(profile.predict(feature: -2), .left)
        XCTAssertEqual(profile.predict(feature: 2), .right)
        XCTAssertEqual(profile.predict(feature: 0), .unknown)

        var invalid = profile
        invalid.schemaVersion += 1
        XCTAssertEqual(invalid.predict(feature: -2), .unknown)
    }

    func testProfileCodableRoundTripPreservesDeterministicDigest() throws {
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-codable",
            lowerBoundary: -1.25,
            upperBoundary: 0.75,
            lowerSide: .right,
            samplesPerGesture: 5
        )

        let decoded = try JSONDecoder().decode(
            TapRegionCalibrationProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.deterministicDigest, profile.deterministicDigest)
    }

    func testFeatureExtractorRequiresPostEventWindowAndTightSync() {
        let baselineAndEarlyWindow = stride(
            from: 0.70,
            through: 1.02,
            by: 0.00125
        ).map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }

        XCTAssertThrowsError(
            try TapRegionFeatureExtractor().extract(
                gyroscope: baselineAndEarlyWindow,
                peakTimestamp: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionFeatureExtractionError,
                .insufficientPostEventData
            )
        }
    }

    func testFeatureExtractorRejectsSparseGyroscopeWindow() {
        let baseline = stride(
            from: 0.75,
            through: 0.92,
            by: 0.00125
        ).map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }
        let sparseWindow = [0.95, 1.0, 1.05].map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }

        XCTAssertThrowsError(
            try TapRegionFeatureExtractor().extract(
                gyroscope: baseline + sparseWindow,
                peakTimestamp: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionFeatureExtractionError,
                .discontinuousGyroscopeData
            )
        }
    }

    func testStreamRejectsNonMonotonicGyroAndBoundsHistory() throws {
        let classifier = try TapRegionStreamClassifier(bufferDurationS: 1)
        for index in 0...1_600 {
            try classifier.append(.imu(
                path: .spuGyroscope,
                sample: IMUSample(
                    timestamp: Double(index) / 800,
                    x: 0,
                    y: 0,
                    z: 0
                )
            ))
        }

        XCTAssertLessThanOrEqual(classifier.bufferedGyroscopeSampleCount, 801)
        XCTAssertThrowsError(try classifier.append(.imu(
            path: .spuGyroscope,
            sample: IMUSample(timestamp: 1, x: 0, y: 0, z: 0)
        )))
    }

    func testCalibrationBuilderQualifiesSeparatedGestureDistributions() throws {
        let gestures = calibrationGestures()

        let result = try TapRegionCalibrationProfileBuilder.build(
            gestures: gestures,
            version: "personal-region-test"
        )

        XCTAssertTrue(result.profile.isValid)
        XCTAssertTrue(result.crossValidationMetrics.qualifies)
        XCTAssertEqual(result.profile.predict(feature: -2), .left)
        XCTAssertEqual(result.profile.predict(feature: 2), .right)
        XCTAssertLessThan(result.profile.lowerBoundary, result.profile.upperBoundary)
    }

    func testCalibrationBuilderRejectsOverlappingSides() {
        var gestures = calibrationGestures()
        gestures = gestures.map {
            var copy = $0
            copy.memberFeatures = Array(
                repeating: 0.1,
                count: copy.pattern.memberCount
            )
            return copy
        }

        XCTAssertThrowsError(
            try TapRegionCalibrationProfileBuilder.build(
                gestures: gestures,
                version: "personal-region-test"
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionCalibrationProfileError,
                .overlappingDistributions
            )
        }
    }

    func testStreamClassifierUsesMedianMembersAndRejectsMissingGyro() throws {
        let classifier = try TapRegionStreamClassifier()
        let peaks = [1.0, 1.3, 1.6]
        for index in 0...1_600 {
            let time = Double(index) / 800
            let relative = peaks.map { time - $0 }
            let x: Double
            if relative.contains(where: { $0 >= -0.02 && $0 < 0 }) {
                x = -4
            } else if relative.contains(where: { $0 >= 0 && $0 <= 0.02 }) {
                x = 1
            } else {
                x = 0
            }
            try classifier.append(.imu(
                path: .spuGyroscope,
                sample: IMUSample(timestamp: time, x: x, y: 0, z: 0)
            ))
        }
        let group = TapGroup(
            members: peaks.map {
                TapEventFeatures(
                    time: $0,
                    peakG: 0.1,
                    decayMs: 20,
                    zImpulseMgS: 0.1,
                    lateralImpulseMgS: 0.1
                )
            },
            verdict: .acceptedComfort
        )
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )

        let result = classifier.classify(group: group, profile: profile)
        let emptyResult = try TapRegionStreamClassifier().classify(
            group: group,
            profile: profile
        )

        XCTAssertEqual(result.prediction, .left)
        XCTAssertEqual(result.reason, .resolved)
        XCTAssertEqual(result.memberFeatures.count, 3)
        XCTAssertEqual(emptyResult.prediction, .unknown)
        XCTAssertEqual(emptyResult.reason, .insufficientGyroscopeData)
    }

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

    private func calibrationGestures() -> [TapRegionCalibrationGesture] {
        var gestures: [TapRegionCalibrationGesture] = []
        for repetition in 1...5 {
            for pattern in TapRegionPattern.allCases {
                for side in TapRegionSide.allCases {
                    let base = side == .left ? -3.0 : 3.0
                    let values = (0..<pattern.memberCount).map {
                        base + Double(repetition) * 0.02 + Double($0) * 0.01
                    }
                    gestures.append(TapRegionCalibrationGesture(
                        side: side,
                        pattern: pattern,
                        repetition: repetition,
                        memberFeatures: values
                    ))
                }
            }
        }
        return gestures
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
