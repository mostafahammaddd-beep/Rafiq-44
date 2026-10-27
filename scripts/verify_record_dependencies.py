#!/usr/bin/env python3
"""Fail CI when record packages resolve to a source-incompatible combination."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


Bounds = tuple[tuple[int, int, int], tuple[int, int, int]]
REQUIRED: dict[str, Bounds] = {
    # record 6.2.1 migrated the platform implementations with the interface.
    "record": ((6, 2, 1), (7, 0, 0)),
    "record_linux": ((1, 3, 1), (2, 0, 0)),
    "record_platform_interface": ((1, 6, 0), (2, 0, 0)),
}
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")


def _version_tuple(value: str) -> tuple[int, int, int]:
    match = VERSION_RE.fullmatch(value.strip())
    if match is None:
        raise ValueError(f"unsupported version string: {value!r}")
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def validate_graph(document: dict[str, Any]) -> list[str]:
    packages = document.get("packages")
    if not isinstance(packages, list):
        return ["flutter pub deps --json did not include a 'packages' list"]

    resolved: dict[str, str] = {}
    for package in packages:
        if isinstance(package, dict) and isinstance(package.get("name"), str) and isinstance(package.get("version"), str):
            resolved[package["name"]] = package["version"]

    errors: list[str] = []
    for name, (minimum, exclusive_maximum) in REQUIRED.items():
        version = resolved.get(name)
        if version is None:
            errors.append(f"required package '{name}' is missing from the resolved dependency graph")
            continue
        try:
            current = _version_tuple(version)
        except ValueError as exc:
            errors.append(f"cannot validate {name}={version}: {exc}")
            continue
        if not (minimum <= current < exclusive_maximum):
            errors.append(
                f"incompatible {name}={version}; expected >= {'.'.join(map(str, minimum))} "
                f"and < {'.'.join(map(str, exclusive_maximum))}"
            )

    if errors:
        errors.insert(
            0,
            "Recorder dependency graph is incompatible. Keep record at ^6.2.1; "
            "do not combine record_linux 0.7.x with record_platform_interface 1.6.x.",
        )
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Usage: {Path(argv[0]).name} <flutter-pub-deps.json>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read dependency graph {path}: {exc}", file=sys.stderr)
        return 2
    if not isinstance(document, dict):
        print("ERROR: dependency graph root must be a JSON object", file=sys.stderr)
        return 2
    errors = validate_graph(document)
    if errors:
        for error in errors:
            print(f"::error::{error}")
        return 1
    packages = {p["name"]: p["version"] for p in document["packages"] if isinstance(p, dict) and "name" in p and "version" in p}
    print("Compatible recorder dependency graph verified:")
    for name in REQUIRED:
        print(f"  {name} {packages[name]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
