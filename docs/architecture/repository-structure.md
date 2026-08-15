# Repository structure

Mactivate separates shipped application code, reusable packages, research, and
developer tooling so each area can be understood and built independently.

## Top-level ownership

- `app/` contains the Xcode application and app-owned tests.
- `packages/core/` contains one Swift package with four products:
  `MactuationCore` (production sensor models and classifiers),
  `MactuationHardware` (macOS IOKit adapters), `MactuationCapture` (on-disk
  session format), and `MactuationTestSupport` (mock/replay sources). Capture
  and test-support are not linked into the shipped application.
- `packages/runtime/` contains product runtime orchestration, persistence, and
  lifecycle handling.
- `research/analysis/` contains offline model fitting and evaluation.
- `research/probe/` contains the hardware discovery and capture CLI.
- `tools/analysis/` contains offline IMU analysis and rule scoring.
- `tools/hardware/` contains daemon-context diagnostics.
- `tools/maintenance/` contains repository layout and boundary checks.
- `docs/` contains architecture, research evidence, and measured probe results.

Local sensor captures remain in the gitignored root `captures/` directory. They
are evidence from a particular machine, not portable repository content.

## Dependency direction

`MactivateApp` depends on `MactivateRuntime`. Runtime depends on
`MactuationCore` and `MactuationHardware`. Hardware depends on Core.

`MactuationResearch` and `MactuationProbe` may depend on production packages,
but production packages never depend on research. Capture and test-support
products are not linked into the shipped application.

App production sources import only `MactivateRuntime` from this repository.
That facade keeps hardware, calibration, and persistence details out of the UI.

## File and directory limits

Handwritten Swift, Python, and shell files must not exceed 300 lines. Split
files by responsibility before adding another exception.

Generated Xcode project metadata and committed data fixtures are exempt because
splitting them would corrupt their format or usefulness. No other exceptions
are implicit.

Each tracked directory has at most 12 immediate entries. Prefer nested groups
that express ownership over flat collections or one-file organizational
wrappers.

Run the policy check from the repository root:

```bash
python3 tools/maintenance/check_repository.py
```

## Comments

Readable names and focused types should explain what the code does. Comments
are reserved for information the code cannot express:

- hardware and operating-system constraints;
- fail-closed and safety rationale;
- calibration provenance and measured boundaries;
- deterministic replay and data-format contracts;
- protocol, compatibility, and toolchain requirements.

Decorative section banners, implementation narration, and comments that repeat
the next statement are removed.

## Tests and evidence

Tests stay with the package or app that owns the behavior. Clone-safe fixtures
remain package resources. Machine-local capture evaluation belongs to research
and may skip when its gitignored evidence is unavailable.

Research documents record observations. The root README defines current product
scope and supported behavior.
