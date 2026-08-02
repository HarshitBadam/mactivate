import XCTest
@testable import MactuationCore

/// Replay-based qualification fixtures: the classifier run over the real
/// 2026-07-24 Mac14,2 captures must reproduce, group for group, the verdicts
/// measured by `scripts/score_rule.py` (which applies the identical rule on
/// top of `scripts/analyze_imu.py`'s pipeline — the project's analysis ground
/// truth). Verdict strings: C = comfort accept, F = firm accept, R = reject,
/// one letter per group in time order.
///
/// Captures are git-ignored and only exist on the target machine; elsewhere
/// these tests skip. They are read-only consumers of `captures/`.
final class TapClassifierCaptureFixtureTests: XCTestCase {
    private struct Fixture {
        let capture: String
        let verdicts: String
        let acceptedCount: Int
    }

    /// Measured 2026-07-24 (scripts/score_rule.py, threshold 0.04 g, no skip,
    /// left-calibrated rule = TapCalibration.mac14_2Discovery).
    ///
    /// Note on the two firm takes: the probe doc's recall numbers (23/26 left,
    /// 24/32 right) were scored without the ≤3-member group-size gate; under
    /// the uniform documented rule ("groups of 1–3 members") firm-tap
    /// aftershocks inflate some groups past 3 members, giving 21/26 and 23/32.
    /// These fixtures pin the uniform-rule outcome. Aftershock suppression is
    /// the known engine refinement that would recover the difference.
    private static let fixtures: [Fixture] = [
        // Positive takes (palm taps).
        Fixture(capture: "20260724-050317-palm_light_800",
                verdicts: "CCCCCCCCCCCCCCCCCCCCCCCCC", acceptedCount: 25),
        Fixture(capture: "20260724-050947-palm_comfort_single_800",
                verdicts: "CCCCCCCCCCCCCCCRCCCC", acceptedCount: 19),
        Fixture(capture: "20260724-051106-palm_comfort_multi_800",
                verdicts: "CCCCCCCCCCCCCCCCCCCCCCCCCCCCC", acceptedCount: 29),
        Fixture(capture: "20260724-051210-palm_comfort_multi_800",
                verdicts: "CCCCCCCCRCCCCCCCRCRCCCCCC", acceptedCount: 22),
        Fixture(capture: "20260724-051318-palm_comfort_multi_800",
                verdicts: "RCCCCCCCCCCCCCCCCCCCCCCCCC", acceptedCount: 25),
        Fixture(capture: "20260724-050217-palm_firm_800",
                verdicts: "RFFFFRFFRFRFFFFFFFFFFFFFFR", acceptedCount: 21),
        Fixture(capture: "20260724-052828-palm_right_single_800",
                verdicts: "CCRCCCCCCCCCCCRCCCCCCCCCRCCC", acceptedCount: 25),
        // Mislabeled on disk; actually the right-palm FIRM take (see probe doc).
        Fixture(capture: "20260724-055005-palm_right_single_800",
                verdicts: "FFFFRRCCCCCRFRCRRCCRCCCCCCRFRCCC", acceptedCount: 23),
        // Adversarial baselines: the zero-false-accept record.
        Fixture(capture: "20260724-050048-baseline_typing_800",
                verdicts: "RR", acceptedCount: 0),
        Fixture(capture: "20260724-050127-baseline_typing_800",
                verdicts: "RRR", acceptedCount: 0),
        Fixture(capture: "20260724-051429-baseline_trackpad_800",
                verdicts: "RRRRRR", acceptedCount: 0),
        Fixture(capture: "20260724-055430-baseline_rest_800",
                verdicts: "", acceptedCount: 0),
        Fixture(capture: "20260724-060733-baseline_bump",
                verdicts: "RRRRRRRR", acceptedCount: 0),
        Fixture(capture: "20260724-063612-baseline_bump_2",
                verdicts: "RRRRRRRRRRR", acceptedCount: 0),
        // Desk knocks sit below the 0.04 g palm threshold entirely.
        Fixture(capture: "20260724-052922-desk_single_800",
                verdicts: "", acceptedCount: 0),
    ]

    private static var capturesRoot: URL {
        // <repo>/MactuationCore/Tests/MactuationCoreTests/ThisFile.swift → <repo>/captures
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MactuationCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MactuationCore
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("captures")
    }

    private func classifiedGroups(for fixture: Fixture) throws -> [TapGroup] {
        let directory = Self.capturesRoot.appendingPathComponent(fixture.capture)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("capture \(fixture.capture) not present on this machine")
        }
        let reader = try CaptureReader(directory: directory)
        let classifier = TapClassifier(calibration: .mac14_2Discovery)
        return classifier.classify(samples: try reader.mergedSamples())
    }

    private func verdictString(_ groups: [TapGroup]) -> String {
        groups.map { group in
            switch group.verdict {
            case .acceptedComfort: return "C"
            case .acceptedFirm: return "F"
            case .rejected: return "R"
            }
        }.joined()
    }

    func testAllFixtureVerdictsMatchAnalyzerGroundTruth() throws {
        for fixture in Self.fixtures {
            let groups = try classifiedGroups(for: fixture)
            XCTAssertEqual(verdictString(groups), fixture.verdicts, fixture.capture)
            XCTAssertEqual(groups.filter { $0.verdict.isAccepted }.count,
                           fixture.acceptedCount, fixture.capture)
        }
    }

    func testAdversarialBaselinesHaveZeroFalseAccepts() throws {
        for fixture in Self.fixtures where fixture.acceptedCount == 0 {
            let groups = try classifiedGroups(for: fixture)
            XCTAssertTrue(groups.allSatisfy { !$0.verdict.isAccepted }, fixture.capture)
        }
    }

    func testCaptureReplayIsByteIdenticalAcrossRuns() throws {
        // Full replay path (reader → merged samples → classifier → digest),
        // twice from disk, must agree byte for byte — Local Probe Plan Step 10.1.
        let fixture = Self.fixtures[0]
        let classifier = TapClassifier(calibration: .mac14_2Discovery)
        let first = classifier.digest(of: try classifiedGroups(for: fixture))
        let second = classifier.digest(of: try classifiedGroups(for: fixture))
        XCTAssertEqual(first, second)
    }
}
