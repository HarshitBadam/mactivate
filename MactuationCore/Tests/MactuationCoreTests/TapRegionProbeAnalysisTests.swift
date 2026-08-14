import XCTest
@testable import MactuationCore

final class TapRegionProbeAnalysisTests: XCTestCase {
    func testFitFindsStableGyroscopeSignAcrossForceLevels() throws {
        let observations = [
            observation(.left, .comfort, -1.8),
            observation(.left, .comfort, -2.2),
            observation(.left, .firm, -4.0),
            observation(.left, .firm, -4.5),
            observation(.right, .comfort, 1.7),
            observation(.right, .comfort, 2.1),
            observation(.right, .firm, 3.8),
            observation(.right, .firm, 4.4)
        ]

        let fit = try TapRegionProbeAnalyzer.fit(observations)

        XCTAssertEqual(fit.model.featureName, "gyro_y_impulse_25_deg")
        XCTAssertTrue(fit.metrics.qualifies)
        XCTAssertEqual(fit.metrics.correct, observations.count)
        XCTAssertEqual(fit.metrics.incorrect, 0)
    }

    func testThresholdModelReturnsAmbiguousInsideGuardBand() {
        let model = TapRegionThresholdModel(
            featureName: "gyro_y_impulse_25_deg",
            lowerBoundary: -0.5,
            upperBoundary: 0.5,
            lowerSide: .left
        )

        XCTAssertEqual(model.predict(observation(.left, .comfort, -1)), .left)
        XCTAssertEqual(model.predict(observation(.right, .comfort, 1)), .right)
        XCTAssertEqual(model.predict(observation(.left, .comfort, 0)), .ambiguous)
    }

    func testRegularizedLinearFitCombinesGyroscopeAxes() throws {
        var observations: [TapRegionProbeObservation] = []
        for repetition in 1...5 {
            for intensity in TapRegionProbeIntensity.allCases {
                observations.append(linearObservation(
                    .left,
                    intensity,
                    repetition: repetition,
                    x: -2 + Double(repetition) * 0.03,
                    y: 1,
                    z: -0.5
                ))
                observations.append(linearObservation(
                    .right,
                    intensity,
                    repetition: repetition,
                    x: 2 - Double(repetition) * 0.03,
                    y: -1,
                    z: 0.5
                ))
            }
        }

        let fit = try TapRegionLinearProbeAnalyzer.fit(observations)
        let crossValidation = try TapRegionLinearProbeAnalyzer.crossValidate(
            observations
        )

        XCTAssertTrue(fit.metrics.qualifies)
        XCTAssertTrue(crossValidation.metrics.qualifies)
        XCTAssertEqual(crossValidation.metrics.incorrect, 0)
    }

    func testMultiTapStrategiesUseCompleteHeldOutGestures() throws {
        var gestures: [TapRegionMultiTapGesture] = []
        for repetition in 1...5 {
            for pattern in TapRegionMultiTapPattern.allCases {
                for side in TapRegionProbeSide.allCases {
                    let sign = side == .left ? -1.0 : 1.0
                    let members = (0..<pattern.memberCount).map { member in
                        TapRegionProbeObservation(
                            side: side,
                            intensity: pattern.analysisIntensity,
                            repetition: repetition,
                            peakTimestamp: Double(member),
                            features: [
                                "gyro_x_peak_deg_s": sign *
                                    (2 + Double(member) * 0.1)
                            ]
                        )
                    }
                    gestures.append(TapRegionMultiTapGesture(
                        side: side,
                        pattern: pattern,
                        repetition: repetition,
                        members: members
                    ))
                }
            }
        }

        let results = try TapRegionMultiTapProbeAnalyzer.screen(gestures)
        let fitted = try TapRegionMultiTapProbeAnalyzer.fitStrategies(gestures)

        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy {
            $0.trainingMetrics.qualifies &&
                $0.crossValidationMetrics.qualifies
        })
        XCTAssertTrue(results.contains { $0.name == "unanimous-vote" })
        XCTAssertTrue(results.contains { $0.name == "majority-vote" })
        XCTAssertEqual(fitted.count, 5)
        XCTAssertTrue(fitted.allSatisfy {
            TapRegionMultiTapProbeAnalyzer.evaluate(
                $0,
                gestures: gestures
            ).qualifies
        })
    }

    func testExtractsSynchronizedFeaturesFromLabelledCapture() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("region-analysis-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SessionManifest(
            label: "region-test",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            toolVersion: "test"
        )
        let writer = try CaptureWriter(
            directory: directory,
            manifest: manifest
        )
        let taps: [(time: Double, side: TapRegionProbeSide,
                    intensity: TapRegionProbeIntensity)] = [
            (1, .left, .comfort),
            (2, .right, .comfort),
            (3, .left, .firm),
            (4, .right, .firm)
        ]
        let rate = 1_000.0
        for index in 0...5_000 {
            let time = Double(index) / rate
            let matchingTap = taps.first { abs($0.time - time) <= 0.010 }
            let accelSpike = taps.contains { abs($0.time - time) < 0.0001 }
            let gyroY: Double
            if let matchingTap {
                gyroY = matchingTap.side == .left ? -20 : 20
            } else {
                gyroY = 0
            }
            try writer.append(.imu(
                path: .spuAccelerometer,
                sample: IMUSample(
                    timestamp: time,
                    x: 0,
                    y: 0,
                    z: accelSpike ? 1.25 : 1
                )
            ))
            try writer.append(.imu(
                path: .spuGyroscope,
                sample: IMUSample(
                    timestamp: time,
                    x: 0,
                    y: gyroY,
                    z: 0
                )
            ))
        }
        for (index, tap) in taps.enumerated() {
            writer.addLabel(LabelSpan(
                start: tap.time - 0.15,
                end: tap.time + 0.15,
                label: "palm-\(tap.side.rawValue)",
                repetition: index + 1,
                intensity: tap.intensity.rawValue
            ))
        }
        try writer.finalize()

        let observations = try TapRegionProbeAnalyzer.observations(
            from: CaptureReader(directory: directory)
        )

        XCTAssertEqual(observations.count, 4)
        XCTAssertLessThan(
            observations[0].features["gyro_y_impulse_25_deg"] ?? 0,
            0
        )
        XCTAssertGreaterThan(
            observations[1].features["gyro_y_impulse_25_deg"] ?? 0,
            0
        )
        XCTAssertTrue(try TapRegionProbeAnalyzer.fit(observations).metrics.qualifies)
    }

    private func observation(
        _ side: TapRegionProbeSide,
        _ intensity: TapRegionProbeIntensity,
        _ value: Double
    ) -> TapRegionProbeObservation {
        TapRegionProbeObservation(
            side: side,
            intensity: intensity,
            repetition: 1,
            peakTimestamp: 0,
            features: ["gyro_y_impulse_25_deg": value]
        )
    }

    private func linearObservation(
        _ side: TapRegionProbeSide,
        _ intensity: TapRegionProbeIntensity,
        repetition: Int,
        x: Double,
        y: Double,
        z: Double
    ) -> TapRegionProbeObservation {
        TapRegionProbeObservation(
            side: side,
            intensity: intensity,
            repetition: repetition,
            peakTimestamp: 0,
            features: [
                "gyro_x_peak_deg_s": x,
                "gyro_y_peak_deg_s": y,
                "gyro_z_peak_deg_s": z
            ]
        )
    }
}
