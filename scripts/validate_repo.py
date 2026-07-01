#!/usr/bin/env python3
"""Validate DBA Toolbox repository conventions.

This intentionally uses only the Python standard library so it can run on a
fresh workstation and in GitHub Actions without dependency bootstrapping.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_FILES = sorted(ROOT.glob("**/*.sql"))
REQUIRED_HEADER_FIELDS = [
    "Script:",
    "Purpose:",
    "Compatible:",
    "Requires:",
    "Impact:",
    "Scope:",
]
REQUIRED_ASSETS = [
    "LICENSE",
    ".editorconfig",
    ".gitignore",
    "docs/script-catalog.md",
    "runbooks/day-one-instance-review.md",
]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def main() -> int:
    if not SQL_FILES:
        fail("No SQL files found")

    missing_assets = [path for path in REQUIRED_ASSETS if not (ROOT / path).exists()]
    if missing_assets:
        fail(f"Missing required assets: {missing_assets}")

    header_failures: dict[str, list[str]] = {}
    for path in SQL_FILES:
        text = path.read_text(encoding="utf-8")
        head = text[:900]
        missing = [field for field in REQUIRED_HEADER_FIELDS if field not in head]
        if missing:
            header_failures[str(path.relative_to(ROOT))] = missing
        if "STRING_AGG" in text.upper() and "SQL Server 2016+" in text:
            fail(f"{path.relative_to(ROOT)} uses STRING_AGG but claims SQL Server 2016+")
        if ("ALTER " in text or "CREATE DATABASE" in text) and ("'[' +" in text or "+ ']'" in text):
            fail(f"{path.relative_to(ROOT)} builds identifiers with manual brackets; use QUOTENAME")

    if header_failures:
        fail(f"SQL scripts missing metadata headers: {header_failures}")

    print(f"OK: validated {len(SQL_FILES)} SQL scripts and repository assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
