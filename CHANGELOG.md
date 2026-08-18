# Changelog

## [1.0.2](https://github.com/HarshitBadam/mactivate/compare/v1.0.1...v1.0.2) (2026-08-18)


### Features

* add calibrated left/right double and triple palm-tap actions ([29b9ae8](https://github.com/HarshitBadam/mactivate/commit/29b9ae85daaae310b683726bc51b06769e911b33))
* add calibrated palm taps, seamless notch UI, and unified action setup ([d7a19eb](https://github.com/HarshitBadam/mactivate/commit/d7a19eb9022d8e02344fa44020d09b86b317cd5c))
* add hardware probe, offline palm-tap classification, capture/replay coverage, and Mac14,2 validation findings for narrowed v1 scope ([be0c8e3](https://github.com/HarshitBadam/mactivate/commit/be0c8e34f86cbac623a4441d2177e19938b7d615))
* record probe compatibility and isolate processing ([3ee4acf](https://github.com/HarshitBadam/mactivate/commit/3ee4acfe66573f8c9fe553bf5babe0eacf25354d))
* **release:** automate ad-hoc DMG releases and document the personal Homebrew tap workflow ([1c5ae5d](https://github.com/HarshitBadam/mactivate/commit/1c5ae5dd6b3332211be224dc1920b22dd1beb806))
* **runtime:** add MactivateRuntime intent-only sensor coordinator ([08fefa7](https://github.com/HarshitBadam/mactivate/commit/08fefa7e26c7c0fa2a3ade0d7e76fb2a147d00d4))
* **sensor-engine:** add live tap streaming, ALS panel hints, and MactuationHardware extraction ([42140ef](https://github.com/HarshitBadam/mactivate/commit/42140efb1feb2b1d09b3dc653f5c3dae75c6220a))
* **ui:** add MactivateApp menu-bar shell with notch panel, quick actions, and safe action dispatch ([95fb0c9](https://github.com/HarshitBadam/mactivate/commit/95fb0c9be435700988c7a97bacebdcdcc779d893))
* **ui:** add palm rest actions toggle and fix hyphenation, toggle sizing, and dot-connector cleanup across settings ([381b9b2](https://github.com/HarshitBadam/mactivate/commit/381b9b245e4ce98b221a3c9148d56e220ba99238))
* **ui:** restyle settings into a graphite three-pane panel with guided calibration and action creation ([8bd8dd1](https://github.com/HarshitBadam/mactivate/commit/8bd8dd1be4970f72da885ec54a90fa165aadac04))


### Bug Fixes

* harden sensor startup concurrency and menu-bar launch diagnostics ([c60f9f7](https://github.com/HarshitBadam/mactivate/commit/c60f9f75a28956b070ac05bde7138070a57612e3))
* **release:** bootstrap patch history and standardize release notes ([970d725](https://github.com/HarshitBadam/mactivate/commit/970d72529fc811fd5ce48251c1f7783b8d0aa9fd))
* **release:** publish immutable v1.0.1 ([a13ac15](https://github.com/HarshitBadam/mactivate/commit/a13ac155d0ecf52fdb79428cae2097e967e00f99))
* **release:** satisfy Homebrew cask style ([4d22322](https://github.com/HarshitBadam/mactivate/commit/4d22322c68a0d9846e392230d65ae1ed1ebef871))
* shorten tap grouping to 300ms and count only valid calibration samples ([495328f](https://github.com/HarshitBadam/mactivate/commit/495328f833780d277d9b57b0da5c035e37eafc17))
* **ui:** polish configuration and notch panel behavior ([d96007e](https://github.com/HarshitBadam/mactivate/commit/d96007e0a23e8d8f2de0f175fe897959ad53219b))

## [1.0.1](https://github.com/HarshitBadam/mactivate/compare/v1.0.0...v1.0.1) (2026-08-16)

### Bug Fixes

- Harden immutable release publication and Homebrew cask delivery.

## [1.0.0](https://github.com/HarshitBadam/mactivate/releases/tag/v1.0.0) (2026-08-15)

### Features

- Publish the initial sensor-driven palm-rest gesture and Notch Panel release.
