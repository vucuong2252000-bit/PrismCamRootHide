#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import py_compile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def validate_plists() -> None:
    paths = list(ROOT.rglob("*.plist")) + list(ROOT.rglob("*.entitlements"))
    for path in paths:
        with path.open("rb") as handle:
            plistlib.load(handle)
        print("plist ok:", path.relative_to(ROOT))


def validate_control() -> None:
    fields = {}
    for line in (ROOT / "control").read_text(encoding="utf-8").splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key] = value.strip()
    required = {"Package", "Name", "Version", "Architecture", "Depends", "Description"}
    missing = required - fields.keys()
    if missing:
        raise SystemExit(f"control thiếu: {sorted(missing)}")
    if fields["Architecture"] != "iphoneos-arm64e":
        raise SystemExit("RootHide A13 build phải dùng iphoneos-arm64e")
    print("control ok")


def validate_paths() -> None:
    forbidden = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix in {".png", ".jpg", ".deb"}:
            continue
        if path.name in {"README.md", "validate_project.py"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "/var/jb" in text:
            forbidden.append(str(path.relative_to(ROOT)))
    if forbidden:
        raise SystemExit(f"Không được hard-code /var/jb trong RootHide: {forbidden}")
    print("RootHide path audit ok")


def validate_braces() -> None:
    for path in [*ROOT.rglob("*.m"), *ROOT.rglob("*.h"), *ROOT.rglob("*.xm")]:
        text = path.read_text(encoding="utf-8")
        stack = []
        pairs = {"}": "{", ")": "(", "]": "["}
        opening = set(pairs.values())
        index = 0
        quote = None
        while index < len(text):
            char = text[index]
            following = text[index + 1] if index + 1 < len(text) else ""
            if quote:
                if char == "\\":
                    index += 2
                    continue
                if char == quote:
                    quote = None
                index += 1
                continue
            if char in {'"', "'"}:
                quote = char
                index += 1
                continue
            if char == "/" and following == "/":
                newline = text.find("\n", index + 2)
                index = len(text) if newline < 0 else newline + 1
                continue
            if char == "/" and following == "*":
                end = text.find("*/", index + 2)
                if end < 0:
                    raise SystemExit(f"Comment chưa đóng: {path.relative_to(ROOT)}")
                index = end + 2
                continue
            if char in opening:
                stack.append(char)
            elif char in pairs:
                if not stack or stack.pop() != pairs[char]:
                    raise SystemExit(f"Ngoặc không cân bằng: {path.relative_to(ROOT)}")
            index += 1
        if stack:
            raise SystemExit(f"Ngoặc chưa đóng: {path.relative_to(ROOT)}")
    print("Objective-C/Logos brace audit ok")


def main() -> None:
    validate_plists()
    validate_control()
    validate_paths()
    validate_braces()
    py_compile.compile(str(ROOT / "tools" / "obs_relay.py"), doraise=True)
    print("obs_relay.py syntax ok")


if __name__ == "__main__":
    main()
