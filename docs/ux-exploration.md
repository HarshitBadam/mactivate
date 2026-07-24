# UX Exploration

Mactivate has one primary interaction model: moving a hand near the MacBook's camera/notch area opens a **large notch-attached mapping workspace**. The menu-bar app is a secondary fallback and configuration entry point.

The surface itself is achievable with AppKit plus permissively licensed prior art (DynamicNotchKit, Perch, OpenNook); see [Prior Art §F](research/prior-art.md#f-notch--top-center-ui) and [Sensor Landscape](research/sensor-landscape.md). Reliable sensor-driven opening remains a hypothesis that must be tested.

## Surface and interaction

- **Closed state:** a minimal notch-adjacent presence; it should not compete with normal work.
- **Primary open trigger:** a hand approaching the camera/notch area.
- **Expanded state:** a notch-attached workspace occupying approximately 60% of the screen, with enough room to present physical tap regions and their shortcut mappings clearly.
- **Secondary entry:** clicking the menu-bar app opens the workspace or fuller settings when hand-near detection is unavailable or the user needs deeper configuration.
- **Hand-near sensor preference:** ambient-light sensing is preferred. Camera sensing is allowed as a fallback, with explicit permission and an explanation that macOS will show its green privacy indicator.
- **Tap sensor preference:** accelerometer sensing is preferred. Microphone sensing is allowed as fallback or fusion, with explicit permission and an explanation that macOS will show its orange privacy indicator.
- **Supported tap vocabulary:** single, double, and triple taps on calibrated palm-rest or nearby-table regions.
- **Unsupported tap vocabulary:** cross-region sequences and rhythms such as left → right → left.

---

## Flows

### First-run setup
- Walk through sensor access and capability discovery with minimal steps.
- Request camera or microphone permission only if the preferred private sensor path fails and the user elects to enable that fallback.
- Explain privileged helper access and macOS privacy indicators before requesting permission. State plainly that continuous fallback detection may keep the green camera or orange microphone indicator visible.
- Never silently switch to camera or microphone when a preferred sensor fails.

### Capability discovery
- Mirror prior art's **live-waveform "Test" panel** (Tapify, Knock): show the raw signal reacting so the user *sees* which capabilities their machine actually has. Ties directly to the probe's device-presence results.
- Present each capability as a card with a clear state: **Available / Unavailable / Needs permission / Experimental**. Unavailable is a first-class, non-error state (graceful degradation rule).

### Calibration
- For taps: visually select a palm-rest or nearby-table region, then "tap N times where you'll actually tap" to capture samples and set thresholds/adaptive parameters.
- Calibrate single, double, and triple timing for each supported region; do not expose arbitrary rhythm or sequence creation.
- For hand-near: a "wave over the notch a few times" step measures the preferred ambient-light signal against environmental drift. If camera fallback is selected, calibrate it separately.
- Always end calibration with a **confidence read-out** ("detected 9/10 taps, 0 false fires") rather than a silent "done."

### Mapping an input to an action
- Use the expanded workspace to show calibrated physical regions spatially.
- Selecting a region exposes exactly three bindings: **single tap**, **double tap**, and **triple tap**.
- Each binding maps directly to an action (open URL, screenshot, run Shortcut, run shell command, or app/window/pointer workflow).
- Keep the action model open-ended (per the vision) — a small set now, extensible later; do not force a final action architecture into the UI.

### Daily use
- Move a hand near the notch to open the large mapping workspace.
- Tap a calibrated palm-rest or nearby-table region once, twice, or three times to run its mapped action.
- Use the menu-bar entry when physical opening is unavailable or for full settings and diagnostics.
- Acknowledge an accepted tap immediately and run its action exactly once. Ambiguous input gets no success feedback and runs nothing.

### Sensor and privacy status
- The workspace and menu-bar surface always identify the active hand-near and tap sensor paths.
- When camera or microphone fallback is active, show a persistent in-app privacy status that matches the macOS green/orange indicator and explains why the device is in use.
- Provide a one-click control to disable each fallback. Stopping a trigger or quitting the app must release its capture device promptly.
- Permission denial is a stable capability state, not an error loop: do not repeatedly prompt or quietly downgrade to another privacy-sensitive path.
- Recording raw camera frames or microphone audio for diagnostics requires separate, explicit consent from enabling live detection.

### Unavailable-sensor diagnostics
- A dedicated "Diagnostics" view in the full editor restates capability states with the *reason* (device absent / permission not granted / experimental-and-unreliable-here) and a re-run-probe action. This is where a failed [probe](local-probe-plan.md) result becomes a calm, explanatory UI, not a crash.

### Non-notch fallback behavior
- No notch → the same large workspace attaches to a floating top-center surface.
- No usable hand-near trigger → the menu-bar icon opens the workspace. Tap actions can continue if tap sensing works.

---

## UI/UX acceptance criteria

- Opening and closing never steals focus unexpectedly, traps the pointer, or interrupts the foreground app unless the user interacts with the workspace.
- Sensor work and action execution never block the main thread; animations and direct manipulation remain smooth under continuous capture.
- Every state has a clear presentation: calibrating, ready, low confidence, unavailable, permission required, helper disconnected, and action failed.
- Mapping edits are predictable and reversible. Destructive changes require confirmation or offer undo, and bindings never change silently.
- Keyboard navigation, VoiceOver labels, sufficient contrast, reduced-motion behavior, and predictable focus order are required.
- Relaunch, sleep/wake, screen changes, sensor interruption, and helper reconnection restore a known state without duplicate actions or stale privacy status.

---

## Scope guardrail

The current UX must not add lid gestures, device movement/orientation gestures, or arbitrary multi-region tap sequences. Research into those capabilities does not make them product features.
