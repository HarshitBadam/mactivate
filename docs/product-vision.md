# Product Vision

Mactivate is an authorized personal macOS hardware-exploration proof of concept. It explores turning physical MacBook interactions and internal hardware signals into configurable shortcuts, commands, and actions. It should feel like a persistent, playful physical layer for a MacBook — not a conventional settings utility.

This document separates four kinds of statements so we never confuse a preference with a fact:

- **Deliberate product choices** — decisions about what we want to build. Revisable, but ours to make.
- **Source-backed technical facts** — claims supported by external documentation, code, or teardown notes, cited elsewhere in `docs/research/`. Facts about *some* hardware per *someone's* report, not yet locally validated.
- **Hypotheses to test** — plausible but unconfirmed; each needs local evidence before it becomes a feature.
- **Open questions** — things we do not yet know and have not yet framed as a testable hypothesis.

---

## The intended daily experience

### Deliberate product choices

- Mactivate runs continuously as a menu-bar / background macOS application and can launch at login.
- The primary interaction is moving a hand near the camera/notch area to expand a large notch-attached workspace, approximately 60% of the screen. This is deliberately much larger than a conventional notch utility because it must provide enough room to configure tap regions and their shortcut mappings.
- Ambient-light sensing — the internal sensing path associated with automatic display-brightness/True Tone behavior — is preferred for hand-near detection. Camera input is an acceptable fallback if needed, but is less desirable because it is more privacy-sensitive and displays macOS's green camera-use indicator.
- The menu-bar app is the reliable secondary entry point. Clicking it can open the large workspace or a fuller configuration surface, but this is not intended to be the main daily interaction.
- The only physical actions currently in product scope are taps on the MacBook palm rests and on the table immediately surrounding the MacBook. Each region supports single, double, and triple taps.
- Tap sequences or combinations across regions (for example, left → right → left) are explicitly out of scope.
- The MacBook's accelerometer is the preferred tap signal. Microphone input is an acceptable fallback or fusion signal if mechanical sensing is insufficient, but is less desirable because it is more privacy-sensitive and displays macOS's orange microphone-use indicator.
- The app must explain and request camera or microphone access only if one of those fallback paths is actually used.
- The app must degrade gracefully when a preferred sensor is unavailable and retain the menu-bar path when hand-near detection cannot work.

### Source-backed technical facts

- A persistent, top-center notch drop-down UI is achievable on macOS: multiple projects implement notch-fused and floating pill surfaces using AppKit `NSPanel` / borderless non-activating windows plus `NSScreen` notch geometry. See [Prior Art](research/prior-art.md) and [Sensor Landscape](research/sensor-landscape.md).
- Launch-at-login, menu-bar presence, and global hotkeys are standard, documented macOS capabilities.

### Hypotheses to test

- **H-VISION-1:** The ambient-light sensor can serve as the primary hand-near trigger for the large notch workspace, reliably enough to feel intentional and without excessive false positives. Camera-based detection remains a fallback, not the preferred implementation. See [Gesture Hypotheses](research/gesture-hypotheses.md).
- **H-VISION-2:** Accelerometer data can reliably distinguish single, double, and triple taps on the palm rests and nearby table. Microphone input remains a fallback or fusion option, not the preferred implementation.
- **H-VISION-3:** The physical-trigger experience is compelling enough to be the primary interaction on supported hardware, with the menu-bar path as fallback rather than the default.

### Open questions

- How much of the experience must survive when the physical trigger is unavailable before the product still feels like "Mactivate" rather than a generic launcher?
- On a Mac with an external display and a MacBook lid open/closed in various states, where should the surface appear?
- Exactly which tap regions should the mapping workspace expose, and how should the user calibrate their boundaries?

---

## The intended workflow

### Deliberate product choices

1. Install Mactivate.
2. Complete setup and discover the Mactuation capabilities available on the current MacBook.
3. Calibrate hand-near detection and the supported palm-rest/table tap regions.
4. In the large notch workspace, map each region's single, double, or triple tap to a shortcut or action.
5. Move a hand near the notch to open the workspace; use the menu-bar app when the physical trigger is unavailable or deeper configuration is needed.

### Why this shape

Capability discovery comes *before* calibration, and calibration comes *before* mapping, because we do not assume any given input exists on any given machine. The workflow is built around empirical capability detection, matching the engineering rule that unsupported hardware must degrade gracefully rather than crash.

---

## Actions

### Deliberate product choices

Initial action ideas, none of which should force a final action architecture now:

- Open a specific website (e.g. Gmail or GitHub).
- Take a screenshot.
- Run a macOS Shortcut.
- Run a configured shell command.
- Trigger app, window, keyboard, or pointer workflows.
- Support future action types without committing to a final action model yet.

### Source-backed technical facts

Each of these is achievable on macOS with known APIs and known permission requirements (opening URLs needs none; screenshots need Screen Recording; input synthesis needs Accessibility; app control needs Automation). Details and citations are in [Sensor Landscape → Actions](research/sensor-landscape.md#actions-and-macos-workflows).

### Open questions

- What is the right abstraction boundary for "an action" so that shell, Shortcut, URL, and synthetic-input actions share a model without over-designing before we have real mappings?

---

## Current product boundary

The first product is intentionally narrow:

- **In scope:** hand-near opening of the large notch workspace; palm-rest and nearby-table tap regions; single/double/triple classification; calibration; region-to-action mapping; privacy-aware sensor fallbacks; menu-bar access.
- **Not in scope:** lid gestures, pickup/tilt/shake/orientation gestures, elaborate tap rhythms, or sequences that combine multiple regions.

Research may record other hardware capabilities, but they must not expand the product or its UI unless this boundary is deliberately revised.

---

## Product quality bar

Determinism, stability, reliability, and polished UI/UX are product requirements, not later cleanup:

- **Deterministic classification:** replaying the same captured sensor stream with the same versioned configuration must produce the same events and timing decisions. Prefer inspectable signal processing and state machines; any learned model must use a frozen model/version and deterministic inference.
- **Exactly-once actions:** one accepted gesture produces one action. Debounce, cooldown, and action dispatch must prevent duplicate execution.
- **Fail closed:** ambiguous or low-confidence input does nothing. A missed gesture is preferable to an unintended shortcut.
- **Measured reliability:** no classifier ships based on a successful demo. It must pass repeatable labelled-data, false-positive, long-idle, typing/trackpad, desk-bump, relaunch, sleep/wake, and sensor-disconnect tests on supported hardware.
- **Stable configuration:** mappings and calibration are versioned, validated, and saved atomically. Invalid or incompatible state falls back safely and is explained; it never silently changes a binding.
- **Graceful degradation:** sensor, helper, permission, or action failures must not crash or hang the app. The UI must identify the unavailable capability and retain the menu-bar path.
- **Responsive UI:** sensor processing and action execution stay off the main thread. Opening, closing, mapping, and diagnostics must remain smooth and must visibly acknowledge accepted input without blocking the user.
- **Accessible, consistent UX:** support keyboard navigation, VoiceOver labels, sufficient contrast, reduced motion, predictable focus, undo/confirmation for destructive mapping changes, and clear empty/error/loading states.

### Privacy-indicator behavior

- Ambient-light and accelerometer paths are preferred partly because they avoid macOS camera/microphone privacy indicators.
- Camera and microphone fallbacks are **never enabled automatically**. The user must deliberately opt in after seeing that continuous detection may keep the green camera or orange microphone indicator visible.
- While either fallback is active, Mactivate must show the active sensor and why it is running, provide a one-click way to disable it, and never imply that the macOS indicator can or should be hidden.
- Disabling a fallback, disabling its trigger, or quitting Mactivate must release that capture device promptly. Permission denial must degrade calmly without repeated prompts.
- Raw camera frames and microphone audio are processed locally and ephemerally by default. They are not stored, transmitted, or included in diagnostics unless the user separately consents to a clearly identified capture session.

---

## Scope posture (carried from the project brief)

- This project intentionally explores beyond documented public macOS APIs. Undocumented/private frameworks, raw IOKit/HID interfaces, reverse-engineered hardware protocols, and privileged helpers are explicitly **in scope** for future Mactuation research.
- Research paths are not rejected merely because they are unsupported by Apple, fragile across macOS versions, unsuitable for the App Store, or may require elevated privileges.
- The owner has authorized this as ethical personal research. **No public claim of Apple endorsement** will be made unless formal evidence is later added; this is project context only.
- Do not assume a hardware capability is unavailable simply because no documented API exists — research prior art and identify evidence, requirements, and unknowns.
- Compatibility, HID usages, privilege requirements, sampling rates, and gesture-classification quality are treated as **empirical questions**, not settled facts.

## Distribution posture

Distribution is explicitly **out of scope** for this task. The eventual product may be installed from GitHub, via a CLI workflow, or through Homebrew, but these concerns must not influence hardware exploration, architecture selection, API choices, privilege requirements, or proof-of-concept design. No distribution documentation, installation method, or mass-distribution optimization is being produced yet.
