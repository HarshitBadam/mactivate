import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimeTapRoutingTests: XCTestCase {
    func testRoutesAllFourSpatialGesturesAndKeepsSingleNonActionable() throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let configuration = RuntimeConfiguration(
            spatialTapBindings: SpatialTapBindings(
                leftDouble: "left.double",
                leftTriple: "left.triple",
                rightDouble: "right.double",
                rightTriple: "right.triple"
            ),
            panelHintsEnabled: false
        )
        let harness = try makeHarness(factory: factory, configuration: configuration)
        harness.controller.start()

        sendIMU(
            to: tapSource,
            duration: 10,
            pulses: [
                (1.0, 0, 0, 0.08),
                (3.0, 0, 0, 0.08),
                (3.4, 0, 0, 0.08),
                (6.0, 0, 0, 0.08),
                (6.35, 0, 0, 0.08),
                (6.7, 0, 0, 0.08)
            ]
        )
        sendIMU(
            to: tapSource,
            startTime: 10,
            duration: 8,
            pulses: [
                (11.0, 0, 0, 0.08),
                (11.4, 0, 0, 0.08),
                (14.0, 0, 0, 0.08),
                (14.35, 0, 0, 0.08),
                (14.7, 0, 0, 0.08)
            ],
            gyroSide: .right
        )
        harness.drain()

        let actions = actionIntents(in: harness.collector.outputs)
        XCTAssertEqual(actions.map(\.0), [
            ActionIdentifier(rawValue: "left.double"),
            ActionIdentifier(rawValue: "left.triple"),
            ActionIdentifier(rawValue: "right.double"),
            ActionIdentifier(rawValue: "right.triple")
        ])
        XCTAssertEqual(actions.map(\.1.gesture), [
            .leftDouble, .leftTriple, .rightDouble, .rightTriple
        ])
        XCTAssertEqual(Set(actions.map(\.1.eventID)).count, 4)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .acceptedNonActionable(.single) &&
                $0.acceptanceVerdict == .acceptedComfort
        })

        harness.controller.stop()
    }

    func testDisabledSpatialDispatchKeepsFeedbackWithoutPerformingAction()
        throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let configuration = RuntimeConfiguration(
            spatialTapBindings: SpatialTapBindings(
                leftDouble: "left.double"
            ),
            spatialTapDispatchEnabled: false,
            panelHintsEnabled: false
        )
        let harness = try makeHarness(
            factory: ScriptedSourceFactory(tapSources: [tapSource]),
            configuration: configuration
        )
        harness.controller.start()

        sendIMU(
            to: tapSource,
            duration: 4,
            pulses: [(1, 0, 0, 0.08), (1.4, 0, 0, 0.08)]
        )
        harness.drain()

        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .dispatchDisabled(.leftDouble) &&
                $0.regionMemberFeatures.count == 2
        })
        harness.controller.stop()
    }
}
