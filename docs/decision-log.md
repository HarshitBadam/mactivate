# Decision Log

A concise record of decisions that have **actually** been made. Hypotheses, options, and preferences live in the other docs — only settled decisions belong here. Each entry: date, decision, rationale, and status.

Format: newest first.

---

### 2026-07-21 — Hardware-independent Mactuation Engine core implemented before the probe
- **Decision:** Implementation starts with `MactuationCore`, a Swift package containing only the parts of the engine that do not depend on unverified hardware facts: typed sensor samples and paths, the capability state model (all real paths default to `unknown`), the capture-session format from the Local Probe Plan Step 7 (per-path CSV streams, `labels.csv`, `session.json`), a deterministic replay source, a stream digest for the deterministic-replay quality gate, and a seeded mock source. Real acquisition adapters (SPU HID, DisplayServices ALS, consented fallbacks) remain probe deliverables and are not written off-Mac.
- **Rationale:** The recorder/replay/labelled-data workflow is required regardless of which sensor paths survive the probe, and building it first means the probe tool lands on tested infrastructure. Writing IOKit adapters without the target machine would encode unvalidated report layouts, wake sequences, and privilege assumptions. The package is Foundation-only so its tests also run off-Mac.
- **Status:** Active. The first hardware code remains the probe tool per the Local Probe Plan handoff.

### 2026-07-21 — ALS placement evidence upgrades hand-near geometry; region localization gets its own hypothesis
- **Decision:** Teardown evidence (iFixit 2021 MacBook Pro X-ray; leaked camera-module photo) placing the ALS inside the notch left of the camera is recorded in the Sensor Landscape; H-HAND-NEAR's placement risk is downgraded while its rate risk stands. Spatial tap localization is promoted from an implicit product assumption to an explicit hypothesis (H-TAP-REGION) backed by `Gojaehyeon/knocker`'s left/right/center X-impulse classification, with left/right/center labelled takes and an ALS shadow-geometry sweep added to the probe plan.
- **Rationale:** The prior research audit found placement and region localization were the two weakest links between the sensor evidence and the promised product; both now have concrete external evidence and falsifiable local tests.
- **Status:** Active. Both remain unvalidated locally.

### 2026-07-21 — Determinism, measured reliability, privacy clarity, and polished UX are release requirements
- **Decision:** Identical recorded input plus identical versioned configuration must classify identically; accepted events dispatch exactly once; ambiguous input fails closed. Product qualification requires repeated labelled sessions, lifecycle/interruption tests, and a long representative false-positive run. Camera/microphone fallbacks are explicit opt-ins with persistent truthful status, prompt device release, and no raw-media retention without separate consent. Accessibility and responsive, non-blocking UI are part of acceptance.
- **Rationale:** Physical sensors are noisy and privacy-sensitive actions can be disruptive. “Works in a demo” is insufficient for a background utility that runs shortcuts or keeps a macOS privacy indicator active.
- **Status:** Active. Initial numerical gates are documented in [Gesture Hypotheses](research/gesture-hypotheses.md) and may be tightened as target-hardware evidence accumulates.

### 2026-07-21 — First product scope narrowed to hand-near opening and simple taps
- **Decision:** The primary experience is a hand near the camera/notch area opening a notch-attached workspace occupying approximately 60% of the screen. That workspace maps calibrated palm-rest and nearby-table regions' single, double, and triple taps to actions. The menu-bar app is secondary. Cross-region sequences, arbitrary rhythms, lid gestures, and movement/orientation gestures are out of scope.
- **Rationale:** A narrow interaction vocabulary keeps the first product centered on its distinctive physical interaction and gives the large surface one clear job: spatial tap-region mapping.
- **Sensor preference:** Prefer ambient-light sensing over camera input for hand-near detection and accelerometer sensing over microphone input for taps. Camera and microphone remain acceptable fallbacks because reliability is unvalidated, but should be avoided when possible due to privacy sensitivity and macOS's green/orange privacy indicators.
- **Status:** Active. The sensor implementations remain hypotheses subject to the local probe; the product boundary is a deliberate choice.

### 2026-07-21 — Documentation, guidelines, and conventions may evolve when evidence supports a change
- **Decision:** The `docs/` content and [Engineering Guidelines](engineering-guidelines.md) are explicitly revisable. When local evidence (or better external evidence) supports a different architecture, capability model, sensor path, UI, or workflow, the relevant document is to be updated and the reasoning recorded here.
- **Rationale:** The project brief and engineering rules both state current sensor/UI/distribution/classification ideas must not be treated as frozen; treating this as a standing decision prevents doc-rot and keeps the research honest.
- **Status:** Active.

### 2026-07-21 — Current hardware assumptions are hypotheses, not facts
- **Decision:** Every claim about the target MacBook's sensors — that the SPU accelerometer/gyroscope is present and root-gated, that ALS and lid angle are readable, HID usages/offsets/scales, sample rates, units, and model/macOS compatibility — is recorded as **source-backed prior art or hypothesis**, never as a locally validated fact, until the [Local Probe Plan](local-probe-plan.md) confirms it on the actual hardware.
- **Rationale:** This work was initialized in a non-macOS cloud environment with no access to the target MacBook, so no hardware behavior could be observed. Prior art is consistent and credible but is other people's reports on other machines; several details already conflict across sources (e.g. lid-angle units, exact model compatibility).
- **Status:** Active. To be revised entry-by-entry as probe results arrive.

### 2026-07-21 — Architecture remains open until local sensor evidence exists
- **Decision:** No final architecture is selected. The [Architecture Options](architecture-options.md) doc states only a *preliminary* lean (self-contained Mactuation Engine with a clean boundary; start in-process/`sudo` for the probe phase; a small privileged helper as the likely product shape). The binding choice is deferred until the probe establishes real privilege requirements and achievable rate/latency.
- **Rationale:** The privilege domain of the sensors (root) and of the actions (TCC grants), the achievable IPC throughput, and even which sensors need root are all unmeasured. Committing to an architecture now would encode unvalidated assumptions.
- **Status:** Active. Revisit after Probe Step 4 (privileges) and any IPC rate measurement.

---

## Deliberately *not* decided yet

Recorded so their openness is intentional, not forgotten:
- Final sensor implementation for hand-near and taps after preferred paths and fallbacks are probed.
- The action-model abstraction (kept open per the product vision).
- Implementation language/framework specifics beyond "native macOS, likely Swift."
- Distribution method (explicitly out of scope for this task).
- Whether to depend on an existing notch library or build the surface in-house.
