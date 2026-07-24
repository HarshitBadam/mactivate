# Architecture Options

Three possible future shapes for how Mactivate's UI/action layer and its Mactuation Engine (sensor layer) relate. **No final choice is made here** — the deciding evidence (privilege requirements, achievable sample rate, latency) does not exist until the [Local Probe Plan](local-probe-plan.md) runs on the target MacBook. This document frames the trade-offs and states a *preliminary* lean with its assumptions exposed.

## The forces at play

Two facts from research shape everything below (see [Sensor Landscape](research/sensor-landscape.md)):

- **The sensor paths and the action paths live in different privilege domains.** SPU IMU access needs **root**; the action layer needs **user-consented TCC grants** (Accessibility, Screen Recording, Automation). A single process would have to hold both, which is a large, awkward trust surface.
- **Prior art already demonstrates a clean split.** `taigrr/apple-silicon-accelerometer` runs a root `sensord` that publishes to an unprivileged `sensordash` over shared memory — a working instance of the daemon model at ~100 Hz.

## Option 1 — Single app process reads the sensors directly

The Mactivate app itself opens the IOKit HID devices and runs the Mactuation Engine in-process alongside the UI and actions.

| Dimension | Assessment |
|---|---|
| Privileges | The **entire app** must run with root (or embed a privileged path) to read the SPU IMU. Broad, uncomfortable privilege for a UI app. |
| Security boundary | Weakest — root and TCC-granted automation in one process; a bug in UI code runs as root. |
| Debugging | Simplest — one process, one log, no IPC. |
| Crash isolation | Worst — a sensor-driver quirk can crash the whole UI, violating "unsupported hardware must not crash the app." |
| Sensor data rate | Highest possible — no IPC hop; direct callback delivery. |
| Latency | Lowest — in-process callback to classifier to UI. |
| Local dev workflow | Easiest to start; `sudo`-run the app during development. |
| Flexibility | Low — sensor and UI lifecycles are coupled; hard to reuse the engine headless. |
| Needs local validation | Whether root-for-the-whole-app is even acceptable; whether an in-process HID crash really takes down the UI on this macOS version. |

## Option 2 — Mactivate app + privileged Mactuation helper/service

The UI/action app runs unprivileged; a small **privileged helper** (e.g. a `SMAppService`/launchd daemon) holds root, reads the sensors, and hands events to the app over a narrow local channel (XPC).

| Dimension | Assessment |
|---|---|
| Privileges | Root confined to a **small, auditable helper**; the UI app stays unprivileged and holds only its TCC grants. Best-practice separation. |
| Security boundary | Strong — the privileged surface is minimal and does one job; the UI cannot escalate. |
| Debugging | Moderate — two components + XPC; standard macOS tooling, but helper install/versioning adds friction. |
| Crash isolation | Good — a helper crash can be restarted by launchd without killing the UI; the app degrades to "sensor unavailable." |
| Sensor data rate | High — XPC can carry ~100 Hz event streams comfortably; raw high-rate streaming needs care but is feasible. |
| Latency | Low — one IPC hop; fine for tap/gesture timescales. |
| Local dev workflow | Heavier — installing/updating a privileged helper is the classic macOS pain point (signing, `SMAppService` registration, teardown). |
| Flexibility | High — the engine is reusable and independently updatable; UI can be replaced without touching the privileged code. |
| Needs local validation | Exactly which operations require root (maybe only some sensors do — lid/ALS may not); XPC throughput at target rates; helper-install UX. |

## Option 3 — Standalone Mactuation sensor daemon + narrow local protocol

A fully independent daemon (its own process/executable) reads the sensors and exposes a **narrow local protocol** (shared memory, a local socket, or XPC) that any client — the Mactivate app, a CLI, a test harness — can consume. This is the `sensord`/`sensordash` model generalized.

| Dimension | Assessment |
|---|---|
| Privileges | Root confined to the daemon; multiple unprivileged clients. Similar boundary to Option 2 but with a **public-ish local API** rather than a private app↔helper link. |
| Security boundary | Strong, but the local protocol is an attack/abuse surface that must be access-controlled (who may connect?). |
| Debugging | Best for the *engine* — the daemon is inspectable standalone (attach a CLI, replay captures) independent of the UI; worst for *end-to-end* (most moving parts). |
| Crash isolation | Best — daemon, UI, and any CLI fail independently. |
| Sensor data rate | Highest of the split options — shared-memory ring buffers proven at ~100 Hz+ (taigrr). |
| Latency | Low for shared memory; slightly higher than in-process. |
| Local dev workflow | Best for **iterating on the engine** (record/replay, headless capture, offline classifier work — matches the probe plan) but most infrastructure to stand up. |
| Flexibility | Highest — clean engine/UI/tooling separation; directly enables the probe's capture→offline-analysis loop. |
| Needs local validation | Protocol choice (shm vs. socket vs. XPC) against measured rate/latency; access control; whether the extra process is worth it vs. Option 2's helper. |

## Preliminary recommendation (revisable)

**Design the Mactuation Engine as a self-contained module with a narrow, transport-agnostic interface, and start development in Option 1's shape (in-process, `sudo`-run) purely for probe/prototype speed — while keeping the engine boundary clean enough to move to Option 2 (privileged helper) for any real build.**

Rationale and assumptions:

- The **probe phase** favors Option 1/Option 3 ergonomics: run headless, `sudo`, record raw data, iterate offline. Standing up a signed privileged helper before we even know which sensors need root would be premature.
- For a **usable product**, Option 2's small privileged helper is the best privilege/crash-isolation trade-off, and the sensor↔UI privilege split makes a single root UI (pure Option 1) hard to justify.
- Option 3 is the natural evolution **if** engine tooling (capture/replay/CLI) becomes central, which the probe plan suggests it will — so the engine's interface should be designed as if a process boundary could exist, even while it starts in-process.

**Assumptions that must hold for this lean (all currently unvalidated):**
1. The SPU IMU requires root on the target machine (Confirmed-external, unverified locally).
2. ~100 Hz event delivery over XPC or shared memory meets tap/gesture latency needs (Reported via `sensord`; unmeasured for our UI).
3. Lid/ALS may *not* need root, meaning some capabilities could work unprivileged even if the IMU cannot — which would change how much lives in the privileged component.

If Step 4 of the probe shows the IMU is readable without root, or that XPC cannot sustain the needed rate, this recommendation should be revisited and the change logged in the [Decision Log](decision-log.md).
