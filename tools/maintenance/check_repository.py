#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath


MAX_LINES = 300
MAX_ITEMS_PER_DIRECTORY = 12
SOURCE_SUFFIXES = {".py", ".sh", ".swift"}
EXPECTED_ROOT_ITEMS = {
    ".gitignore",
    "LICENSE",
    "README.md",
    "app",
    "docs",
    "packages",
    "research",
    "tools",
}


def repository_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
    )
    return Path(result.stdout.strip())


def tracked_paths(root: Path) -> list[PurePosixPath]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    paths = [
        PurePosixPath(value.decode())
        for value in result.stdout.split(b"\0")
        if value
    ]
    return [path for path in paths if (root / path).is_file()]


def line_limit_errors(root: Path, paths: list[PurePosixPath]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        if path.suffix not in SOURCE_SUFFIXES:
            continue
        line_count = len((root / path).read_bytes().splitlines())
        if line_count > MAX_LINES:
            errors.append(f"{path}: {line_count} lines (maximum {MAX_LINES})")
    return errors


def directory_fanout_errors(paths: list[PurePosixPath]) -> list[str]:
    children: dict[PurePosixPath, set[str]] = defaultdict(set)
    for path in paths:
        parts = path.parts
        for index, child in enumerate(parts):
            parent = PurePosixPath(*parts[:index])
            children[parent].add(child)

    errors: list[str] = []
    for parent, items in sorted(children.items(), key=lambda item: str(item[0])):
        if len(items) <= MAX_ITEMS_PER_DIRECTORY:
            continue
        label = str(parent) if str(parent) != "." else "<root>"
        errors.append(
            f"{label}: {len(items)} tracked items "
            f"(maximum {MAX_ITEMS_PER_DIRECTORY})"
        )
    return errors


def root_layout_errors(paths: list[PurePosixPath]) -> list[str]:
    root_items = {path.parts[0] for path in paths}
    unexpected = sorted(root_items - EXPECTED_ROOT_ITEMS)
    missing = sorted(EXPECTED_ROOT_ITEMS - root_items)
    errors = [f"unexpected root item: {item}" for item in unexpected]
    errors.extend(f"missing root item: {item}" for item in missing)
    return errors


def imports(path: Path) -> set[str]:
    modules: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        tokens = line.strip().split()
        if not tokens or (tokens[0] != "import" and not tokens[0].startswith("@")):
            continue
        if "import" not in tokens:
            continue
        index = tokens.index("import") + 1
        if index >= len(tokens):
            continue
        if tokens[index] in {
            "class", "enum", "func", "let", "protocol", "struct",
            "typealias", "var",
        }:
            index += 1
        if index < len(tokens):
            modules.add(tokens[index].split(".")[0])
    return modules


def boundary_errors(root: Path, paths: list[PurePosixPath]) -> list[str]:
    forbidden_by_prefix = {
        "app/MactivateApp/": {
            "MactuationCapture",
            "MactuationCore",
            "MactuationHardware",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Sources/MactuationCore/": {
            "MactivateRuntime",
            "MactuationCapture",
            "MactuationHardware",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Sources/MactuationHardware/": {
            "MactivateRuntime",
            "MactuationCapture",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Sources/MactuationCapture/": {
            "MactivateRuntime",
            "MactuationHardware",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Sources/MactuationTestSupport/": {
            "MactivateRuntime",
            "MactuationHardware",
            "MactuationResearch",
        },
        "packages/runtime/Sources/MactivateRuntime/": {
            "MactuationCapture",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Tests/": {
            "MactuationResearch",
        },
        "packages/runtime/Tests/": {
            "MactuationResearch",
        },
    }

    errors: list[str] = []
    for path in paths:
        if path.suffix != ".swift":
            continue
        value = str(path)
        for prefix, forbidden in forbidden_by_prefix.items():
            if not value.startswith(prefix):
                continue
            violations = sorted(imports(root / path) & forbidden)
            if violations:
                errors.append(f"{path}: forbidden imports {', '.join(violations)}")
    return errors


def dependency_manifest_errors(root: Path) -> list[str]:
    forbidden_by_path = {
        "app/MactivateApp.xcodeproj/project.pbxproj": {
            "MactuationCapture",
            "MactuationCore",
            "MactuationHardware",
            "MactuationResearch",
            "MactuationTestSupport",
        },
        "packages/core/Package.swift": {
            "MactivateRuntime",
            "MactuationResearch",
        },
        "packages/runtime/Package.swift": {
            "MactuationCapture",
            "MactuationResearch",
            "MactuationTestSupport",
        },
    }
    errors: list[str] = []
    for relative_path, forbidden in forbidden_by_path.items():
        contents = (root / relative_path).read_text(encoding="utf-8")
        violations = sorted(name for name in forbidden if name in contents)
        if violations:
            errors.append(
                f"{relative_path}: forbidden dependencies {', '.join(violations)}"
            )
    return errors


def main() -> int:
    root = repository_root()
    paths = tracked_paths(root)
    checks = [
        ("root layout", root_layout_errors(paths)),
        ("directory fan-out", directory_fanout_errors(paths)),
        ("source line limits", line_limit_errors(root, paths)),
        ("module boundaries", boundary_errors(root, paths)),
        ("dependency manifests", dependency_manifest_errors(root)),
    ]

    failures = False
    for name, errors in checks:
        if not errors:
            print(f"PASS {name}")
            continue
        failures = True
        print(f"FAIL {name}")
        for error in errors:
            print(f"  {error}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
