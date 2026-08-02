# Sensor & Interface Landscape

An evidence-backed survey of the hardware signals and system interfaces Mactivate might use. Every meaningful claim links to a source. **None of this has been validated on the target MacBook yet** — see [Local Probe Plan](../local-probe-plan.md).

## How to read the confidence column

- **Confirmed (external):** demonstrated by working code or documentation on *some* Apple Silicon MacBook, cited. Still unverified on *our* target hardware.
- **Reported:** described by one or more sources as working, but with thin evidence, version/model caveats, or conflicting details.
- **Hypothesis:** plausible from adjacent evidence, not directly demonstrated for this use.

## Capability table

| Sensor / interface | Likely hardware models | Access method | Privilege | Known data rate | Confidence | Possible Mactivate use | Sources |
|---|---|---|---|---|---|---|---|
| **SPU accelerometer** (3-axis, believed Bosch BMI286) | Apple Silicon MacBooks: M2/M3/M4/M5; M1 **Pro** reported OK, base M1 (2020) reported not; no accelerometer on desktop/Studio | `AppleSPUHIDDevice` via IOKit HID; usage page `0xFF00`, usage `3`; `IOHIDDeviceRegisterInputReportCallback`; 22-byte reports, int32 LE at offsets 6/10/14, ÷65536 → g | **root (sudo)** | ~800 Hz native, decimated to ~100 Hz by default (decimation 8) | Confirmed (external) | Preferred palm-rest / chassis / nearby-table tap detection | [1][2][3][4] |
| **SPU gyroscope** (3-axis, same IMU) | Same as SPU accelerometer | Same device; usage `9`; int32 LE ÷65536 → deg/s | **root (sudo)** | Same path as accelerometer | Confirmed (external) | Optional secondary feature for tap classification | [1][2] |
| **Ambient Light Sensor via SPU HID** | Apple Silicon MacBooks with SPU | Same `AppleSPUHIDDevice`; usage `4` (per Apple Wiki `0xFF00`/usage 4); olvvier exposes `read_als()` → lux + 4 spectral channels | **root (sudo)** likely (same HID path) | Snapshot/low rate; ALS `ReportInterval` default `5428500`, lowerable | Reported | Top-display hand-near / cover detection; light-based trigger | [1][4][6] |
| **Ambient Light Sensor via DisplayServices** | Apple Silicon MacBooks (built-in display) | `DisplayServicesClient` `copyPropertyForKey:` → `AggregatedLux`; mirrors `corebrightnessdiag`/`sysdiagnose` | Unprivileged reported (Hammerspoon runs without root) | Aggregated/slow (brightness-oriented) | Reported | Same as above; likely lower rate but no root | [7][8] |
| **Ambient Light Sensor (Intel path)** | Intel Macs | `AppleLMUController` IOService, `IOConnectCallMethod`, `LMUtoLux()` conversion | Unprivileged reported | Polled | Confirmed (external, Intel only) | Not a target (Mactivate targets Apple Silicon); documented for contrast | [7][8] |
| **Lid angle sensor** | MacBooks 2019+ (Intel and Apple Silicon) | HID device VID `0x05AC`, PID `0x8104` (Sensor Hub), usage page `0x0020`, usage `0x008A`; **Feature Report** ID 1; `(hi<<8)|lo` LE 16-bit | Reported unprivileged (feature report read) | On-demand poll; ~0.1 s monitor loops used | Confirmed (external) | Research reference only; lid gestures are outside current product scope | [9][10][11][12] |
| **Lid angle via SPU HID** | Apple Silicon w/ SPU | Same `AppleSPUHIDDevice`; olvvier exposes `read_lid()` → degrees | **root (sudo)** likely | Snapshot | Reported | Research reference only; outside current product scope | [1] |
| **Microphone (acoustic tap)** | All Macs with a mic | `AVAudioEngine.installTap(onBus:)`; RMS per buffer; delta onset detection | **Microphone (TCC) consent; orange indicator while active** | ~44.1 kHz; ~100 windows/s at 441-frame buffers | Confirmed (external) | Explicitly opted-in fallback/fusion path when preferred mechanical sensing is insufficient | [13][14] |
| **Camera (hand pose / cover)** | All Macs with a camera | AVFoundation + Vision (`VNDetectHumanHandPose`) | **Camera (TCC) consent; green indicator while active** | Video frame rate | Hypothesis | Explicitly opted-in fallback when preferred ambient-light sensing is insufficient | [15] |
| **Notch geometry** | MacBooks with a notch (2021+ 14"/16", later Air) | `NSScreen.safeAreaInsets.top != 0`; `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`; notch width = frame.width − left − right | Unprivileged (public API, macOS 12+) | n/a (static geometry) | Confirmed (external, Apple docs) | Place & size the notch drop-down; detect non-notch fallback need | [16][17] |
| **Top-center overlay window** | All Macs | `NSPanel` `.borderless` + `.nonactivatingPanel`; level `.statusBar+1`; `collectionBehavior` `.canJoinAllSpaces`, `.fullScreenAuxiliary` | Unprivileged (public API) | n/a | Confirmed (external, Apple docs + libs) | Large notch-attached mapping workspace and non-notch top-center fallback | [18][19][20] |

Sources are listed at the bottom of this file.

---

## Detail notes

### Apple Silicon SPU (Sensor Processing Unit) IMU

The strongest and best-corroborated internal-sensor path. Multiple independent implementations (Python, Go, Swift) agree on the mechanism:

- The IMU lives under **`AppleSPUHIDDevice`** in the IOKit registry, driven by **`AppleSPUHIDDriver`**, on vendor usage page **`0xFF00`**. **Usage 3** = accelerometer, **usage 9** = gyroscope; same physical part, believed to be a **Bosch BMI286** based on teardowns (an inference, not a confirmed Apple spec). [1][2]
- Access is via `IOHIDDevice*` APIs with an async input-report callback; reports are **22 bytes**, three `int32` little-endian values at byte offsets **6, 10, 14**, divided by **65536** to yield g (accel) or deg/s (gyro). [1][2]
- Native sample rate is **~800 Hz**, commonly **decimated to ~100 Hz**. [1][2]
- **Wake sequence:** the Swift port documents setting `SensorPropertyReportingState`, `SensorPropertyPowerState`, and `ReportInterval` on the `AppleSPUHIDDriver` services before reports flow. [2]
- **Requires root.** All three implementations require `sudo` for IOKit HID access to this device. [1][2][3]
- **Root vs. entitlements:** no source demonstrates an entitlement that grants non-root access to this device. Apple DTS guidance (via an older but still-cited answer) is that direct `IOHIDDeviceOpen` on protected/keyboard-like HID devices requires an interactive-user or root context, and non-sandboxed apps have no entitlement to add. [28] Treat "root, or a root helper" as the working assumption; verify locally at Probe Step 4 and note if any shipping tap app (Tapify, Knock) evidently avoids it.
- **Lateral tap localization is demonstrated externally.** `Gojaehyeon/knocker` classifies palm-rest taps as **left / right / center** from the sign and magnitude of the X-axis impulse (high-pass per axis, ~150 ms integration window around each peak), with per-model calibration required because the IMU's position relative to the chassis varies. [29] This is the strongest external evidence that Mactivate's spatial region mapping is feasible on the same SPU path.
- **Presence check without root:** `ioreg -l -w0 | grep -A5 AppleSPUHIDDevice`, or `IMU.available()` in the Python lib. [1]
- **Locally validated (2026-07-24, Mac14,2, macOS 26.2):** accelerometer (0xFF00/3) and gyroscope (0xFF00/9) present with `sensor_rates` "50 100 200 400 800"; 22-byte reports and the 6/10/14 ÷ 65536 decode **confirmed against gravity**; ~99.7 Hz effective delivery at `ReportInterval` 10000 µs; wake sequence **required** (state properties absent until set). **The root requirement is refuted locally: HID open, wake writes, and delivery all succeeded unprivileged (euid 501) in an interactive user session, twice.** Daemon-context behavior untested. CoreMotion (`CMMotionManager`) reports `accelerometerAvailable = false` at runtime — public-API path refuted. See [Probe Results](../probe-results/2026-07-24-mac14-2-discovery.md).

**Compatibility evidence is fragmentary and must be treated as such.** olvvier reports tested only on **MacBook Pro M3 Pro, macOS 15.6.1**, and lists **known incompatible**: Intel Macs (no SPU), **M1 MacBook Pro (2020)**, and **Mac Studio M4 Max** (desktop — no accelerometer). [1] section9-lab claims **M2/M3/M4/M5, and M1 Pro only among M1 variants**. [2] The commercial Knock app lists confirmed devices **MacBook Pro M1–M5 and MacBook Air M2–M4** on macOS Sequoia 15.7+. [21] These are external reports, not our measurements.

### Ambient light — physical placement

Teardown evidence places the ALS **inside the notch itself, immediately left of the camera lens**, on notched MacBook Pro models: iFixit's 2021 MacBook Pro teardown X-ray identifies the ambient light sensor left of the camera sensor with the indicator LED to its right, and a leaked camera-module photo shows the True Tone + ambient light sensor package in the same position. [26][27] This is favorable geometry for a hand-near/cover gesture — a hand over the notch area should shadow the sensor directly — but update cadence and shadow response remain unmeasured. Placement on non-notch models (e.g. pre-2021, or the bezel-camera Air) is unverified and may differ.

### Ambient light — two candidate paths

There appear to be **three distinct ALS access strategies**, with different privilege and rate profiles:

1. **SPU HID (usage 4):** the same `AppleSPUHIDDevice` exposes ALS; olvvier's `read_als()` returns lux plus four spectral channels. The Apple Wiki documents an ALS IOHIDService on page `0xFF00` usage `4` with a default `ReportInterval` of `5428500` that can be lowered for faster reporting. Likely requires root (same HID path). [1][4][6]
2. **DisplayServices `AggregatedLux`:** used by Hammerspoon's brightness extension and LuxCurve; reads an aggregate lux value via `DisplayServicesClient copyPropertyForKey:`. Reported to work **without root**, but the value is brightness-oriented and likely slower/smoothed. [7][8]
3. **Registry poll of `CurrentLux` (locally discovered, 2026-07-24):** on Mac14,2/macOS 26.2 the ALS driver (`AppleSPUVD6286`, usage `0xFF00`/`4`) publishes a live `CurrentLux` registry property readable **unprivileged** via `IORegistryEntry`; observed updating with ambient changes, default `ReportInterval` 197380 (~5 Hz) — note this **conflicts with the Apple Wiki default of 5428500** and must be read-and-restored, not assumed. Update cadence under a deliberate hand shadow is unmeasured and is the deciding question. Not found in any surveyed prior art. See [Probe Results](../probe-results/2026-07-24-mac14-2-discovery.md).

For a hand-near/cover trigger we care about **latency and dynamic range under a shadow**, not calibrated lux — so the higher-rate SPU HID path is more promising *if* root is acceptable, while the DisplayServices path is the unprivileged fallback. Which is usable is an [open probe question](../local-probe-plan.md).

### Lid angle — separate documented-ish HID device

Independently reverse-engineered by **Sam Henri Gold (`samhenrigold/LidAngleSensor`)** and reimplemented in Python, Rust, and C++. Consensus: a HID device at **VID `0x05AC` / PID `0x8104`** (Apple "Sensor Hub"), **usage page `0x0020`**, **usage `0x008A`**, read via **Feature Report ID 1**, angle = 16-bit little-endian from bytes `[1..2]`. [9][10][11][12]

**Conflicting detail to resolve locally:** units. pybooklid reports whole degrees `0–180`; lid-angle-rs and mac-angle report **0.01-degree resolution** and ranges up to 360. This must be measured, not assumed. Some implementations read the feature report without root; confirm on the target machine.

### Microphone as an independent tap path

`MacTapper` demonstrates chassis/desk tap detection purely from the **built-in microphone** via `AVAudioEngine.installTap`, computing RMS per ~441-frame buffer (~100 windows/s) and firing on a **delta spike** (`|rms − prevRMS| > threshold`) with a **350 ms cooldown**. Sensitivity thresholds: `0.005` (light finger tap), `0.010` (solid knock), `0.018` (hard knock). [13] The tap block runs off the main thread; Apple documents `installTap` and its threading caveats. [14] This is valuable as a **second, independent signal** for fusion with the accelerometer — an acoustic transient plus a mechanical transient in the same time window is a much stronger tap hypothesis than either alone.

### Notch UI & top-center overlay (public APIs)

Fully within documented AppKit:

- **Notch detection (macOS 12+):** `NSScreen.safeAreaInsets.top != 0` indicates a notch; `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (both `NSRect?`) give the usable regions beside the camera housing, and notch width = `frame.width − left − right`. [16][17]
- **Overlay window:** a borderless, non-activating `NSPanel` at a high window level (`.statusBar + 1` or `.mainMenu`) with `collectionBehavior` including `.canJoinAllSpaces` and `.fullScreenAuxiliary`. [18][19][20]
- **Fullscreen caveat:** there is no public API to draw into the sensor-housing region during native fullscreen; the workaround is a borderless window sized to `screen.frame` with `presentationOptions` auto-hiding the menu bar and Dock. [17]

See [Prior Art](prior-art.md) for the libraries that package this (DynamicNotchKit, Perch, boring.notch, OpenNook, NotchDrop).

---

## Actions and macOS workflows

Technical requirements and OS permissions for the initial action ideas. App Store restrictions are intentionally **not** a constraint here.

| Action | Mechanism | Permission (TCC) | Notes / source |
|---|---|---|---|
| Open URL | `NSWorkspace.shared.open(url)` | None | Standard, no prompt. |
| Take screenshot | `screencapture` CLI, or `ScreenCaptureKit` / `CGWindowListCreateImage` | **Screen Recording** (`kTCCServiceScreenCapture`) | Without it, captures show only wallpaper. [22][23][24] |
| Run a Shortcut | `shortcuts run "Name"` CLI (macOS 12+) | Depends on what the Shortcut does | CLI is the scriptable entry point. [23] |
| Run AppleScript | `NSAppleScript` / `osascript` | **Automation** (per target app) | Each controlled app triggers its own consent. [22] |
| Run shell command | `Process` / `NSTask` | None for own process; controlled apps need their own TCC grants | — |
| Synthesize keyboard/mouse | `CGEvent` post | **Accessibility** / Input injection (`kTCCServicePostEvent`) | [22][24][25] |
| Read global input (hotkeys/taps) | `CGEventTap` (listen) | **Input Monitoring** (`kTCCServiceListenEvent`) | Only if we intercept system-wide input. [22] |
| App / window control | `AXUIElement` (Accessibility API) | **Accessibility** (`kTCCServiceAccessibility`) | Background-safe automation demonstrated by axcli / computer-use. [24][25] |

**Implication for architecture:** the sensor paths (IOKit HID) that need **root** and the action paths that need **user-consented TCC grants** (Accessibility, Screen Recording, Automation) are *different* privilege domains. This split is a central input to [Architecture Options](../architecture-options.md).

---

## Sources

1. olvvier/apple-silicon-accelerometer (Python, MIT) — https://github.com/olvvier/apple-silicon-accelerometer
2. section9-lab/AppleSPUAccelerometer (Swift) — https://github.com/section9-lab/AppleSPUAccelerometer
3. taigrr/apple-silicon-accelerometer (Go, MIT) — https://github.com/taigrr/apple-silicon-accelerometer
4. pirate/mac-hardware-toys (Python) — https://github.com/pirate/mac-hardware-toys
5. olvvier discovery write-up (Medium) — https://medium.com/@oli.bourbonnais/your-macbook-has-an-accelerometer-and-you-can-read-it-in-real-time-in-python-28d9395fb180
6. Apple Wiki, AppleISL29003 / AppleCT700 ALS IOHIDService — https://theapplewiki.com/wiki/Dev:AppleISL29003
7. Hammerspoon `libbrightness.m` (ambient lux via DisplayServices / AppleLMUController) — https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/brightness/libbrightness.m
8. nonml/LuxCurve (Objective-C/Swift, private-API ambient light menu-bar app) — https://github.com/nonml/LuxCurve
9. samhenrigold/LidAngleSensor (Swift, Apache-2.0) — https://github.com/samhenrigold/LidAngleSensor
10. tcsenpai/pybooklid (Python) — https://github.com/tcsenpai/pybooklid
11. wangfu91/lid-angle-rs (Rust) — https://github.com/wangfu91/lid-angle-rs
12. alessaba gist, read MacBook lid angle in C — https://gist.github.com/alessaba/098f83c587e1372d30dea36a7c18b7cc
13. Nabwinsaud/mac-tapper (Swift, mic-based tap detection) — https://github.com/Nabwinsaud/mac-tapper
14. Apple, `installTap(onBus:bufferSize:format:block:)` — https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)
15. Apple, Vision hand pose (`VNDetectHumanHandPoseRequest`) — https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest
16. Apple, `NSScreen.auxiliaryTopLeftArea` — https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea
17. StackOverflow, detect the MacBook notch / use the area around it — https://stackoverflow.com/questions/69685094/detect-macbook-notch-in-macos-monterey-and-higher
18. Apple, `NSWindow.StyleMask.nonactivatingPanel` — https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
19. MrKai77/DynamicNotchKit (Swift, MIT) — https://github.com/MrKai77/DynamicNotchKit
20. tukuyomil032/Perch (Swift) — https://github.com/tukuyomil032/Perch
21. Knock (commercial) — https://www.tryknock.app/
22. HackTricks, macOS Input Monitoring / Screen Capture / Accessibility (TCC services) — https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-input-monitoring-screen-capture-accessibility.html
23. Podfeet, `screencapture` from the command line — https://www.podfeet.com/blog/2021/05/screencapture-command-line/
24. dnakov/computer-use (macOS control CLI) — https://github.com/dnakov/computer-use
25. andelf/axcli (Accessibility + ScreenCaptureKit CLI) — https://github.com/andelf/axcli
26. iFixit, 2021 MacBook Pro teardown (notch X-ray; ALS left of camera) — https://www.ifixit.com/News/54122/macbook-pro-2021-teardown
27. NotebookCheck, MacBook Pro notch houses True Tone + ambient light sensors — https://www.notebookcheck.net/Apple-MacBook-Pro-s-notch-houses-more-than-just-a-1080p-camera.574456.0.html
28. StackOverflow, daemon HID access / `kIOReturnNotPrivileged` and root requirement — https://stackoverflow.com/questions/13629199/how-can-a-daemon-user-access-hid-devices-without-getting-kioreturnnotprivileged
29. Gojaehyeon/knocker (left/right/center palm-rest tap localization on SPU IMU) — https://github.com/Gojaehyeon/knocker
