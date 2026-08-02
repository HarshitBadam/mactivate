import XCTest
import MactuationCore
@testable import MactivateDesign

final class StatePresentationTests: XCTestCase {
    // MARK: - Activity feed / exactly-once

    func testARedeliveredEventAppearsOnceAndIsCountedAsSuppressed() {
        var feed = ActivityFeed()
        let event = GestureEvent(
            id: "evt-7",
            kind: .tap(region: TapRegionID(surface: .palmRest, zone: .left), count: .double),
            confidence: 0.9,
            timestamp: Date()
        )
        let entry = ActivityEntry(event: event, actionTitle: "GitHub", actionSymbolName: "safari", outcome: .ran)

        XCTAssertTrue(feed.record(entry))
        XCTAssertFalse(feed.record(entry), "A duplicate event ID must not produce a second row.")
        XCTAssertEqual(feed.entries.count, 1)
        XCTAssertEqual(feed.suppressedDuplicateCount, 1)
    }

    func testTheFeedIsNewestFirstAndBounded() {
        var feed = ActivityFeed()
        for index in 0..<(ActivityFeed.capacity + 10) {
            let event = GestureEvent(id: "evt-\(index)", kind: .handNear, confidence: 1, timestamp: Date())
            feed.record(ActivityEntry(event: event, actionTitle: nil, actionSymbolName: nil, outcome: .ran))
        }
        XCTAssertEqual(feed.entries.count, ActivityFeed.capacity)
        XCTAssertEqual(feed.mostRecent?.id, "evt-\(ActivityFeed.capacity + 9)")
    }

    // MARK: - Calibration

    func testCalibrationAlwaysEndsWithAMeasuredReadout() {
        var session = CalibrationSession(
            subject: .tap(region: TapRegionID(surface: .palmRest, zone: .right), count: .double)
        )
        session.apply(.waiting(instruction: "Double tap when the countdown ends."))
        session.apply(.measuringBaseline(secondsRemaining: 3))
        session.apply(.collecting(captured: 0, target: 10))
        for index in 1...9 { session.apply(.captured(index: index, confidence: 0.9)) }

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.progressFraction ?? 0, 0.9, accuracy: 0.001)

        session.apply(.finished(result: CalibrationResult(detected: 9, attempted: 10, falseFires: 0)))
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.instruction, "Detected 9 of 10 taps, 0 false fires")
    }

    func testFalseFiresAreSurfacedDuringCollectionAndAffectTheVerdict() {
        var session = CalibrationSession(subject: .handNear)
        session.apply(.collecting(captured: 2, target: 6))
        session.apply(.falseFire(count: 1))

        guard case .collecting(_, _, let falseFires) = session.phase else {
            return XCTFail("Expected to stay in collecting while reporting a false fire.")
        }
        XCTAssertEqual(falseFires, 1)

        let result = CalibrationResult(detected: 6, attempted: 6, falseFires: 1)
        XCTAssertFalse(result.meetsQualificationBar, "A false fire must fail the bar even at full recall.")
        XCTAssertEqual(result.regionCalibrationState().tone, .attention)
    }

    func testQualificationBarMatchesTheProjectTargets() {
        XCTAssertTrue(CalibrationResult(detected: 10, attempted: 10, falseFires: 0).meetsQualificationBar)
        XCTAssertTrue(CalibrationResult(detected: 19, attempted: 20, falseFires: 0).meetsQualificationBar)
        XCTAssertFalse(CalibrationResult(detected: 9, attempted: 10, falseFires: 0).meetsQualificationBar)
        XCTAssertEqual(CalibrationResult(detected: 3, attempted: 10, falseFires: 0).tone, .failure)
    }

    func testCancellingCalibrationLeavesNoPartialState() {
        var session = CalibrationSession(subject: .handNear)
        session.apply(.collecting(captured: 3, target: 6))
        session.apply(.captured(index: 3, confidence: 0.8))
        session.reset()

        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.capturedConfidences.isEmpty)
    }

    // MARK: - Waveform

    func testAnUnavailableSensorReadsAsAFlatLineRatherThanEmptiness() {
        var buffer = WaveformBuffer(capacity: 10)
        for _ in 0..<10 { buffer.append(0.5) }
        XCTAssertTrue(buffer.isSilent)
        XCTAssertEqual(buffer.plotPoints().count, 10)
    }

    func testTheTraceScrollsInFromTheRightWhileFilling() {
        var buffer = WaveformBuffer(capacity: 8)
        buffer.append(0.9)
        let points = buffer.plotPoints(baseline: 0.5)
        XCTAssertEqual(points.count, 8)
        XCTAssertEqual(points.last, 0.9)
        XCTAssertEqual(points.first, 0.5)
    }

    func testSamplesAreClampedAndBounded() {
        var buffer = WaveformBuffer(capacity: 4)
        for value in [-3.0, 0.25, 9.0, 0.5, 0.75] { buffer.append(value) }
        XCTAssertEqual(buffer.samples.count, 4)
        XCTAssertEqual(buffer.peak, 1.0)
        XCTAssertFalse(buffer.isSilent)
    }

    // MARK: - Engine status headlines

    func testHeadlineLeadsWithWhateverIsMostWrong() {
        var status = PreviewFixtures.status(.everythingWorks)
        XCTAssertEqual(status.headlineTone, .ready)

        status.tap = .unavailable(reason: "No readable motion sensor on this Mac")
        XCTAssertEqual(status.headlineTone, .attention)
        XCTAssertTrue(status.headline.hasPrefix("Taps unavailable"))

        status.helper = .disconnected(reason: "The sensor helper stopped responding.")
        XCTAssertEqual(status.headline, "Sensor helper disconnected")
        XCTAssertEqual(status.headlineTone, .failure)

        status.isPaused = true
        XCTAssertEqual(status.headline, "Mactivate is paused")
        XCTAssertEqual(status.headlineTone, .neutral)
    }

    func testCapturingStateComesFromTheEngineNotFromSettings() {
        let status = PreviewFixtures.status(.cameraFallbackOn)
        XCTAssertTrue(status.isCapturingPrivateSensor)
        XCTAssertEqual(status.activeCaptures.first?.path, .camera)

        let quiet = PreviewFixtures.status(.everythingWorks)
        XCTAssertFalse(quiet.isCapturingPrivateSensor)
    }

    // MARK: - Capability presentation

    func testEveryPathAndStateCombinationProducesUsableCopy() {
        let states: [CapabilityState] = [
            .unknown,
            .available(detail: "100 Hz"),
            .unavailable(reason: "Not present on this Mac."),
            .needsPrivilege(privilege: "administrator approval"),
            .needsOptIn
        ]
        for path in SensorPath.allCases {
            for state in states {
                let presentation = SensorPresentationCatalog.presentation(for: path, state: state)
                XCTAssertFalse(presentation.stateText.isEmpty, "\(path) \(state)")
                XCTAssertFalse(presentation.explanation.isEmpty, "\(path) \(state)")
                XCTAssertFalse(presentation.symbolName.isEmpty, "\(path) \(state)")
                XCTAssertFalse(presentation.sensor.displayName.isEmpty)
            }
        }
    }

    func testUnavailableIsAToneNotAnError() {
        let presentation = SensorPresentationCatalog.presentation(
            for: .spuAccelerometer,
            state: .unavailable(reason: "Not present on this Mac.")
        )
        XCTAssertEqual(presentation.tone, .unavailable)
        XCTAssertNil(presentation.callToAction, "An unavailable sensor must not offer a dead-end button.")
        XCTAssertTrue(presentation.explanation.contains("keeps working"))
    }

    func testPrivacySensitivePathsAlwaysCarryTheIndicatorExplanation() {
        for path in [SensorPath.camera, SensorPath.microphone] {
            let sensor = SensorPresentationCatalog.presentation(for: path)
            XCTAssertTrue(sensor.privacyIndicator.isPrivacySensitive)
            let explanation = sensor.privacyIndicator.explanation ?? ""
            XCTAssertTrue(explanation.contains("macOS shows"))
            XCTAssertTrue(explanation.contains("hide"), "The copy must be explicit that the indicator cannot be hidden.")
        }
        for path in [SensorPath.spuAccelerometer, .spuGyroscope, .spuAmbientLight, .displayServicesAmbientLight] {
            XCTAssertFalse(SensorPresentationCatalog.presentation(for: path).privacyIndicator.isPrivacySensitive)
        }
    }

    func testFallbackRowsDefaultToOffAndSayItIsTheUsersChoice() {
        let triggers = TriggerSettings()
        XCTAssertFalse(triggers.cameraFallbackEnabled)
        XCTAssertFalse(triggers.microphoneFallbackEnabled)

        let row = SensorPresentationCatalog.presentation(for: .camera, state: .needsOptIn, isEnabled: false)
        XCTAssertEqual(row.stateText, "Off — your choice")
        XCTAssertEqual(row.callToAction, "Turn On…")
        XCTAssertEqual(row.tone, .neutral)
    }

    func testCapabilityRowsCoverBothTriggersInPreferenceOrder() {
        let rows = SensorPresentationCatalog.rows(
            from: PreviewFixtures.capabilities(.everythingWorks),
            triggers: TriggerSettings()
        )
        XCTAssertEqual(rows.first?.sensor.path, .spuAmbientLight)
        XCTAssertEqual(rows.map(\.sensor.path).count, Set(rows.map(\.sensor.path)).count)
        XCTAssertTrue(rows.contains { $0.sensor.path == .spuAccelerometer })
    }

    // MARK: - Regions

    func testCollapsedRegionsAreOfferedWhenLocalizationFails() {
        let regions = DefaultConfiguration.collapsedRegions(reason: "Left and right taps were not separable here.")
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions.first?.name, "Palm Rest")
        XCTAssertFalse(regions[1].calibration.allowsBindings)
    }

    func testRegionNamesReadNaturally() {
        XCTAssertEqual(TapRegion.defaultName(surface: .palmRest, zone: .left), "Left Palm Rest")
        XCTAssertEqual(TapRegion.defaultName(surface: .desk, zone: .center), "Desk, In Front")
        XCTAssertEqual(TapRegion.defaultName(surface: .desk, zone: .whole), "Desk")
    }

    func testTheTrackpadIsNeverATapRegion() {
        let regions = DefaultConfiguration.regions()
        for region in regions {
            let frame = region.frame
            let trackpad = DeviceMapLayout.trackpad
            let overlapsTrackpadHorizontally = frame.x < trackpad.x + trackpad.width && trackpad.x < frame.x + frame.width
            let overlapsTrackpadVertically = frame.y < trackpad.y + trackpad.height && trackpad.y < frame.y + frame.height
            if region.id == TapRegionID(surface: .palmRest, zone: .center) {
                // The centre palm region sits behind the trackpad in the drawing;
                // it is the chassis around it, and the map labels it that way.
                continue
            }
            XCTAssertFalse(
                overlapsTrackpadHorizontally && overlapsTrackpadVertically,
                "\(region.name) overlaps the trackpad."
            )
        }
    }

    // MARK: - Motion and time

    func testReduceMotionCollapsesEveryAnimationToACrossFade() {
        let reduced = Motion.Profile(reduceMotion: true)
        XCTAssertFalse(reduced.panelUsesSpring)
        XCTAssertTrue(reduced.crossFadeOnly)
        XCTAssertEqual(reduced.duration(Motion.Duration.stateChange), Motion.Duration.reducedMotionCrossFade)

        let standard = Motion.Profile(reduceMotion: false)
        XCTAssertTrue(standard.panelUsesSpring)
        XCTAssertEqual(standard.duration(Motion.Duration.stateChange), Motion.Duration.stateChange)
    }

    func testRelativeTimeIsTerseOnScreenAndSpokenInFull() {
        let now = Date()
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-2), now: now), "just now")
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-42), now: now), "42s ago")
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-120), now: now), "2m ago")
        XCTAssertEqual(RelativeTime.spoken(from: now.addingTimeInterval(-60), now: now), "1 minute ago")
        XCTAssertEqual(RelativeTime.percent(0.945), "95%")
    }
}
