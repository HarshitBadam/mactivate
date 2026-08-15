# Packages

`packages/` contains the Swift packages used by the shipped application.

- `core/` provides deterministic sensor models and classifiers, macOS hardware adapters, capture storage, and test support as separate products.
- `runtime/` owns product configuration, calibration persistence, tap routing, deduplication, and sleep/wake lifecycle behavior.

The app depends on Runtime, which depends on Core and Hardware. Capture and test-support products are reserved for tests and research.

## Test

```bash
swift test --package-path packages/core
swift test --package-path packages/runtime
```

Production packages never depend on code under `research/`.
