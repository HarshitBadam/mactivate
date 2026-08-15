# Research

`research/` contains the non-shipping code used to discover hardware behavior, capture sensor sessions, fit spatial models, and evaluate classifier changes.

- `analysis/` provides the offline `MactuationResearch` package and capture-backed tests.
- `probe/` provides the `mactuation-probe` command-line tool for discovery, live diagnostics, capture, and spatial validation.

Machine-specific captures stay in the gitignored root `captures/` directory. Portable regression fixtures live with the package tests.

## Build and test

```bash
swift test --package-path research/analysis
swift build --package-path research/probe
```

The measured outcomes are summarized in [product validation](../docs/validation/product-validation.md).
