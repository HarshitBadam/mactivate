# Application

`app/` contains the native macOS menu-bar application. It presents the Notch Panel and a separate Configuration Window while delegating sensor decisions and lifecycle handling to `MactivateRuntime`.

## Layout

- `MactivateApp/App/`: Application lifecycle, state, and runtime bridge
- `MactivateApp/Actions/`: Validated application, URL, Shortcut, and Notch Panel actions
- `MactivateApp/Panel/`: Notch and top-center panel presentation
- `MactivateApp/Settings/`: Configuration Window, onboarding, calibration, diagnostics, and preferences
- `MactivateAppTests/`: App behavior and runtime integration tests

The target runs as a menu-bar agent. The menu bar item opens the Notch Panel and provides access to the Configuration Window.

## Run and test

```bash
open app/MactivateApp.xcodeproj
xcodebuild -project app/MactivateApp.xcodeproj -scheme MactivateApp -destination 'platform=macOS' test
```
