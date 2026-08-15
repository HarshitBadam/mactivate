# Core package

This Swift package separates reusable sensor behavior into four products:

- `MactuationCore`: Sensor contracts and deterministic tap, region, and ambient-light classifiers
- `MactuationHardware`: macOS IOKit accelerometer, gyroscope, and ambient-light adapters
- `MactuationCapture`: Non-shipping capture storage and replay
- `MactuationTestSupport`: Non-shipping mocks, replay sources, and deterministic digests

The shipped runtime links Core and Hardware. Capture and TestSupport are used by tests and research.

```bash
swift test --package-path packages/core
```

Hardware support is capability-detected at runtime, and spatial gestures require personal calibration.
