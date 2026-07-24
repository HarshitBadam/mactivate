# Engineering Guidelines

## Hardware exploration

- Keep undocumented and private sensor APIs behind small capability-detected adapters.
- Treat every hardware claim as unvalidated until a probe records the target model, macOS build, privileges, HID usages, and compatibility result.
- Prefer ambient-light sensing over camera input and accelerometer sensing over microphone input.
- Do not add hardware adapters or classifiers until the probe establishes a usable path and produces labelled captures.

## Reliability

- Process sensor data and execute actions away from the main thread.
- Replay the same capture with the same versioned configuration to produce identical events.
- Use stable event identifiers, exactly-once action dispatch, and fail closed on ambiguous input.
- Exercise relaunch, sleep/wake, permission changes, configuration reload, sensor interruption, and helper restart before release.

## Privacy and capability

- Unsupported hardware must surface an explicit capability state and never crash the app.
- Camera and microphone fallbacks require explicit opt-in, persistent truthful status, prompt release when disabled, and separate consent before retaining raw media.
- Keep feature flags default-off for unvalidated sensor paths and privacy-sensitive fallbacks.

## Qualification and interface

- Qualify classifiers against labelled captures and long false-positive runs per hardware model, sensor path, and operating condition.
- Expose capability, confidence, permission, loading, failure, and privacy states in the interface.
- Support keyboard navigation, VoiceOver, contrast, reduced motion, and predictable focus.
