import XCTest
@testable import MactivateApp

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testSetLaunchAtLoginEnabledUpdatesStatusFromManager() {
        let runtime = FakeRuntime()
        let launchAtLogin = TestLaunchAtLogin()
        let coordinator = makeCoordinator(
            runtime: runtime,
            launchAtLogin: launchAtLogin
        )

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(coordinator.state.launchAtLoginStatus, .enabled)
    }

    func testSetLaunchAtLoginFailureSurfacesWarningWithoutCrashing() {
        let runtime = FakeRuntime()
        let launchAtLogin = TestLaunchAtLogin()
        launchAtLogin.errorToThrow = TestFailure("denied")
        let coordinator = makeCoordinator(
            runtime: runtime,
            launchAtLogin: launchAtLogin
        )

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(coordinator.state.recentWarning, "denied")
    }
}
