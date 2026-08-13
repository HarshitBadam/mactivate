# Prior Art

Projects relevant to Mactivate, grouped by the problem they address. Each entry lists URL, license, language, target hardware/OS, what it proves, key implementation details, limitations, and the lesson for Mactivate.

**Licenses are as observed during research and must be re-verified before any code reuse.** Where the GitHub API reported no license file but a README claims one, that is flagged. Nothing here has been run on the target MacBook.

---

## A. Apple Silicon internal IMU / sensor access

### olvvier/apple-silicon-accelerometer
- **URL:** https://github.com/olvvier/apple-silicon-accelerometer
- **License:** MIT · **Language:** Python · **Target:** Apple Silicon MacBooks (tested MacBook Pro M3 Pro, macOS 15.6.1)
- **Proves:** the SPU IMU is real and readable in real time from user space (with root). This is the reference implementation the Go and Swift ports descend from; ~1.2k stars.
- **Key details:** `AppleSPUHIDDevice`, usage page `0xFF00`, usage 3 (accel) / 9 (gyro); 22-byte HID reports, int32 LE at offsets 6/10/14, ÷65536; ~800 Hz native, decimated to ~100 Hz; also exposes `read_als()` (lux + 4 spectral channels) and `read_lid()`. Ships biquat Butterworth filters, gravity removal, peak detection, Mahony AHRS, record/replay, and a mock mode.
- **Limitations:** requires `sudo`; "may break on future macOS updates"; compatibility explicitly narrow (see README's known-incompatible list); single-author test coverage.
- **Lesson:** the SPU accelerometer is our highest-confidence internal signal. Its mock/record/replay design is a direct model for the Mactivate probe's labelled-data workflow — capture once, iterate on classification offline without hardware.

### section9-lab/AppleSPUAccelerometer
- **URL:** https://github.com/section9-lab/AppleSPUAccelerometer
- **License:** README states MIT; **no LICENSE file detected via API — verify before reuse.** · **Language:** Swift (pure, no C/ObjC bridge) · **Target:** macOS 13+, Apple Silicon MacBooks (M2/M3/M4/M5; "M1 Pro only among M1 variants")
- **Proves:** the whole pipeline — driver wake, HID callback, detection, classification — is achievable in **pure Swift**, which is our likely implementation language.
- **Key details:** documents the **wake sequence** (`SensorPropertyReportingState`, `SensorPropertyPowerState`, `ReportInterval` on `AppleSPUHIDDriver`); layered architecture (`SPUDriver` → `VibrationDetector`/`OrientationTracker`/`TapDetector`/`HeartbeatDetector` → `SPUAccelerometer` facade); **dual-EMA tap detector** (fast ~50 ms vs slow ~500 ms envelope, ratio > 3.0, cooldown, `minGapMs` 100 / `maxGapMs` 450) that needs no hardcoded amplitude threshold; vibration algorithms STA/LTA, CUSUM, Kurtosis, Peak/MAD; amplitude guide (0.05 g slap / 0.01 g table / 0.005 g light).
- **Limitations:** low adoption (early stage); same root requirement and macOS-version fragility; classification thresholds are the author's, not validated for palm-rest vs. desk discrimination.
- **Lesson:** strongest template for the Mactuation Engine's Swift structure and for the tap detector. The layered `SPUDriver`-behind-a-facade shape matches our "isolate unsupported APIs behind adapters" rule almost exactly.

### taigrr/apple-silicon-accelerometer
- **URL:** https://github.com/taigrr/apple-silicon-accelerometer
- **License:** MIT · **Language:** Go (zero-CGO via `purego`) · **Target:** Apple Silicon MacBooks
- **Proves:** the sensor can live in a **standalone daemon** that publishes to consumers over a shared-memory IPC, decoupling privileged capture from unprivileged UI.
- **Key details:** two binaries — `sensord` (root; IOKit HID → POSIX shared-memory ring buffers) and `sensordash` (unprivileged TUI reading shared memory). Ring buffers (accel/gyro): 16-byte header + 8000 × 12-byte entries; snapshots (ALS/lid): 8-byte header + payload; format kept compatible with the Python implementation.
- **Limitations:** Go/purego is not our stack; shared-memory format is bespoke.
- **Lesson:** this is a concrete, working instance of a **daemon + narrow local protocol** architecture. It shows that a privileged/unprivileged split is practical and that a ring-buffer snapshot protocol is enough for ~100 Hz sensor data if Mactivate ever needs a separate sensor process.

### taigrr/spank
- **URL:** https://github.com/taigrr/spank · **License:** MIT · **Language:** Go · **Target:** Apple Silicon MacBooks
- **Proves:** the accelerometer is responsive enough for playful, real-time reactions to physical impacts (a "slap the MacBook" toy); ~4.9k stars shows the interaction resonates.
- **Limitations:** toy scope; no gesture taxonomy beyond impact.
- **Lesson:** validates the *playful physical layer* framing of Mactivate's vision, and that impact detection off the SPU accelerometer is low-latency enough to feel immediate.

### pirate/mac-hardware-toys
- **URL:** https://github.com/pirate/mac-hardware-toys
- **License:** **none detected via API — treat as all-rights-reserved until confirmed.** · **Language:** Python · **Target:** Apple Silicon Macs
- **Proves:** a *composable* view of Mac hardware — accelerometer, gyroscope, ambient-light, lid-angle, and microphone as inputs; keyboard/display brightness, speaker, fan as outputs — all reading through the same AppleSPU HID path (auto-`sudo`).
- **Key details:** confirms **ambient-light and lid-angle read through the same AppleSPU HID path** as the IMU, and that all sensor tools auto-reexec via `sudo`. Uses AppleSMC private IOKit for fans.
- **Limitations:** breadth over depth; no gesture classification; licensing unclear.
- **Lesson:** corroborates ALS + lid on the SPU HID path from a second independent author, and reinforces that most internal-sensor reads share one privileged interface — which argues for a single capability-detected adapter fronting them.

### Gojaehyeon/knocker
- **URL:** https://github.com/Gojaehyeon/knocker · **License:** verify in repo · **Language:** Go (purego sensor path) + GUI · **Target:** Apple Silicon MacBooks
- **Proves:** **spatial tap localization** on the SPU accelerometer — palm-rest taps classified as **left / right / center** and mapped to distinct hotkeys/shell commands. The closest existing analog to Mactivate's region mapping.
- **Key details:** ~100 Hz via `AppleSPUHIDDevice`; high-pass filter per axis; integrates a ~150 ms impulse window around each detected peak; classifies by **X-axis impulse sign and magnitude** against a `lateral_threshold`; per-side cooldown (~450 ms); `flip_x` config because IMU orientation varies; ships `--calibrate` and stresses per-model calibration; live waveform + per-axis impulse log. Requires `sudo`.
- **Limitations:** three coarse regions on one axis, not arbitrary regions; accuracy explicitly model-dependent; single-author.
- **Lesson:** lateral impulse sign/magnitude is a workable first feature for palm-rest region discrimination, and per-machine calibration is non-optional. Directly informs H-TAP-REGION and the probe's left/right labelled takes.

---

## B. Tap / gesture products (what the market has shipped)

### versacecrispies/Tapify
- **URL:** https://github.com/versacecrispies/Tapify · **License:** open source (verify SPDX in repo) · **Language:** Swift + Objective-C · **Target:** Apple Silicon MacBooks
- **Proves:** a free menu-bar app can turn chassis taps into single/double/triple actions using only the accelerometer.
- **Key details:** reads ~100 Hz via IOKit HID (ObjC layer), detects a **Z-axis spike above the ~1 g gravity baseline** vs. a sensitivity threshold, applies a **150 ms lockout** after each tap, then groups taps within a **600–1200 ms gesture window** into single/double/triple. Actions: play/pause, lock, screenshot-with-crop, open app, volume. Live waveform + test mode.
- **Limitations:** single-axis threshold approach; no palm-rest vs. desk discrimination; sensitivity is user-tuned rather than calibrated per surface.
- **Lesson:** the menu-bar + calibration + live-waveform + test-mode UX is exactly our workflow; and it confirms a simple threshold+window classifier is *good enough to ship* — a useful baseline to beat, not a ceiling.

### Knock (tryknock.app) — commercial
- **URL:** https://www.tryknock.app/ · **License:** proprietary · **Target:** Apple Silicon MacBooks (M1–M5), macOS Sequoia 15.7+; also trackpad and iPhone input modes
- **Proves:** commercial viability and the broadest **confirmed device list** we have (MBP M1–M5, MBA M2–M4). Offers single/double/triple patterns → mute, play/pause, lock, launch apps, run Shortcuts, run terminal commands.
- **Key details:** three input modes — native MacBook chassis tap (select models), trackpad-tap (hold a key + tap, works on all Macs), and an iPhone companion (desk/screen tap over LAN). Ships a "Test" panel with a live waveform for compatibility checking.
- **Limitations:** closed source; "native MacBook tapping available on select models" — an honest admission that chassis tapping is hardware-dependent.
- **Lesson:** the **trackpad-tap and companion-device fallbacks** are a strong pattern for our "graceful capability states" — when chassis tapping is unavailable, offer a different physical modality rather than nothing. The Test/waveform panel validates our capability-discovery UX.

### tapcut — commercial
- **URL:** https://tapcut.app/ · **License:** proprietary · **Target:** Apple Silicon MacBooks, macOS 14+
- **Proves:** binding **multi-tap rhythms** (2/3/4) to Shortcuts, app launches, key combos, text snippets works as a product, and explicitly markets "listens for a rhythm, not a bump" — i.e. typing rejection.
- **Limitations:** closed source; desktop Macs excluded (no accelerometer).
- **Lesson:** rhythm-based patterns and explicit false-positive framing ("typing doesn't look like a deliberate double-tap") are the right way to talk about reliability to users.

### Haptyk — commercial
- **URL:** https://haptyk.com · **License:** proprietary · **Target:** Apple Silicon MacBooks
- **Proves:** the accelerometer is sensitive enough to detect **typing force** and react per-keystroke (mechanical keyboard sounds), i.e. sub-tap-magnitude signal is usable.
- **Lesson:** confirms high sensitivity/low latency of the SPU accelerometer, but also that **typing produces a strong, continuous accelerometer signature** — the primary false-positive source our tap classifier must reject.

---

## C. Microphone-based tap detection

### Nabwinsaud/mac-tapper
- **URL:** https://github.com/Nabwinsaud/mac-tapper · **License:** verify in repo · **Language:** Swift · **Target:** any Mac with a microphone
- **Proves:** chassis/desk taps are detectable **acoustically**, independent of the accelerometer, with a trivial DSP pipeline.
- **Key details:** `AVAudioEngine.installTap`, 441-frame buffers @ 44.1 kHz (~100 windows/s), per-window RMS, **delta onset** (`|rms − prevRMS| > threshold`), 350 ms cooldown; thresholds 0.005/0.010/0.018 for light/solid/hard.
- **Limitations:** microphone consent required; susceptible to ambient noise, speech, music; no direction/source discrimination.
- **Lesson:** the microphone is a cheap **second signal for sensor fusion** — an acoustic transient co-occurring with a mechanical transient is a much stronger tap hypothesis. See [Gesture Hypotheses](gesture-hypotheses.md).

---

## D. Lid-angle sensor

### samhenrigold/LidAngleSensor
- **URL:** https://github.com/samhenrigold/LidAngleSensor · **License:** Apache-2.0 · **Language:** Swift · **Target:** MacBooks 2019+
- **Proves:** the lid-angle sensor is directly readable via HID feature reports; the origin of the widely-copied VID/PID/usage recipe (~4.1k stars).
- **Key details:** HID device VID `0x05AC` / PID `0x8104`, usage page `0x0020`, usage `0x008A`; **Feature Report ID 1**, 16-bit LE angle.
- **Lesson:** lid angle is a low-risk, low-rate signal ideal as an early "supported capability" to demo the calibrate→map flow with minimal privilege.

### tcsenpai/pybooklid · wangfu91/lid-angle-rs · ufoym/mac-angle
- **URLs:** https://github.com/tcsenpai/pybooklid · https://github.com/wangfu91/lid-angle-rs · https://github.com/ufoym/mac-angle
- **Licenses/Languages:** Python / Rust / C++ (verify SPDX per repo) · **Target:** modern MacBooks (2019+, incl. Apple Silicon)
- **Prove:** the same recipe reimplemented across three languages — strong cross-corroboration.
- **Key details / conflict:** pybooklid reports whole degrees `0–180`; lid-angle-rs and mac-angle report **0.01-degree resolution** (ranges up to 360). **Units and range differ across implementations and must be measured locally.**
- **Lesson:** even a "solved" sensor has unresolved detail (units); reinforces the rule to *measure*, and gives us three reference decoders to cross-check against.

---

## E. Ambient-light access

### nonml/LuxCurve
- **URL:** https://github.com/nonml/LuxCurve · **License:** verify (private-API app) · **Language:** Objective-C + Swift · **Target:** Apple Silicon Mac w/ built-in display, macOS 14+ (verified M3 MacBook Air, macOS 26.4)
- **Proves:** a shipping menu-bar app can read ambient lux via private frameworks and **isolate all private-API use in a single bridge file** (`LCBridge.m`) — the exact isolation pattern our rules mandate.
- **Key details:** reads light and sets brightness/warmth through `IOKit`/`IOHIDEventSystem`, `DisplayServices`, and CoreBrightness; ships a `Tooling/sensor-probe/` diagnostic to run first when APIs break.
- **Limitations:** private APIs → no App Store, may break across macOS versions (acknowledged).
- **Lesson:** the model citizen for Mactivate's structure — one quarantined bridge file, a standalone sensor-probe diagnostic, and honest documentation of fragility.

### Hammerspoon `hs.brightness`
- **URL:** https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/brightness/libbrightness.m · **License:** MIT · **Language:** Objective-C · **Target:** macOS (Intel + Apple Silicon)
- **Proves:** aggregate ambient lux is obtainable **without root** on Apple Silicon via `DisplayServicesClient` `AggregatedLux` (the `corebrightnessdiag`/`sysdiagnose` method), with an Intel `AppleLMUController` fallback.
- **Lesson:** gives us the unprivileged ALS fallback path and a battle-tested reference for it; contrasts with the higher-rate-but-root SPU HID ALS path.

---

## F. Notch / top-center UI

### MrKai77/DynamicNotchKit
- **URL:** https://github.com/MrKai77/DynamicNotchKit · **License:** MIT · **Language:** Swift/SwiftUI · **Target:** macOS 13+ (notch and non-notch Macs)
- **Proves:** a reusable library can present arbitrary SwiftUI content from the notch and **automatically fall back to a floating style on non-notch Macs** — exactly our required fallback behavior.
- **Key details:** `DynamicNotch { ContentView() }` + `await notch.expand()`; also `DynamicNotchInfo` / `DynamicNotchProgress`; configurable transition animations; handles insets/safe areas.
- **Lesson:** the leading candidate to prototype the notch drop-down quickly (MIT, SwiftUI-native), and a reference even if we later build our own panel. Its `.auto`/`.floating` style switch is the pattern for notch↔fallback.

### tukuyomil032/Perch
- **URL:** https://github.com/tukuyomil032/Perch · **License:** verify · **Language:** Swift · **Target:** macOS (notch + non-notch)
- **Proves:** a persistent **top-center pill that fuses into the notch or floats on non-notch Macs**, launches at login, hover-expands and auto-collapses — essentially the shell of Mactivate's surface.
- **Key details:** clean AppKit/SwiftUI split — `IslandWindow` (transparent `NSWindow` overlay), `NotchDetector`, `IslandGeometry` (per-screen frame math), `MouseEventMonitor` (hover/click); SwiftUI `CompactPillView`/`ExpandedIslandView`; Metal metaball transition. Notes it is **not sandbox-compatible** (uses methods incompatible with the sandbox) — matching our private-API/non-App-Store posture.
- **Lesson:** the closest structural analog to Mactivate's UI layer. Its AppKit-window / SwiftUI-content split is a useful model, and its candid "not sandboxable" note matches the constraints of private sensor APIs.

### TheBoredTeam/boring.notch
- **URL:** https://github.com/TheBoredTeam/boring.notch · **License:** GPL-3.0 · **Language:** Swift · **Target:** MacBooks with a notch
- **Proves:** a full, popular (~10k stars) notch app — hover-expand, media controls, file shelf, HUD replacement — is sustainable.
- **Limitations:** **GPL-3.0 is copyleft**; reading for patterns is fine, but linking/adapting code would impose GPL on Mactivate. Keep at arm's length for licensing.
- **Lesson:** rich source of interaction patterns; a licensing caution flag; and its dependence on `NotchDrop` and a media-remote adapter shows how these apps compose smaller components.

### OpenNook (glendonC/opennook) · Lakr233/NotchDrop
- **URLs:** https://github.com/glendonC/opennook · https://github.com/Lakr233/NotchDrop
- **Licenses:** OpenNook Apache-2.0 (its `NookSurface` subtree MIT, a trimmed fork of DynamicNotchKit); NotchDrop (verify) · **Language:** Swift · **Target:** macOS notch apps
- **Prove:** the notch-panel chrome (shape geometry, hover, expand/collapse lifecycle, frosted backdrop, global hotkey, settings shell, menu-bar fallback) is generalizable into a framework; NotchDrop is a widely-reused transparent-window/notch-detection base.
- **Lesson:** confirms a permissively-licensed (Apache/MIT) path to the notch chrome exists if we don't want to depend on GPL code, and enumerates the exact chrome features our surface needs.

---

## G. Action / automation tooling (reference, not dependency)

### dnakov/computer-use · andelf/axcli
- **URLs:** https://github.com/dnakov/computer-use · https://github.com/andelf/axcli
- **Languages:** native macOS binaries · **Target:** macOS 14+
- **Prove:** background-safe screenshots (ScreenCaptureKit, no focus steal), input synthesis (CGEvent), and app/window control (AXUIElement) are all achievable from a CLI, with explicit TCC handling (`check/request-accessibility`, `check/request-screen-recording`).
- **Lesson:** concrete references for implementing the action layer and for the **permission-request UX** — they enumerate exactly which TCC grants each action needs, feeding [Sensor Landscape → Actions](sensor-landscape.md#actions-and-macos-workflows).
