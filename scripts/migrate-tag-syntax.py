#!/usr/bin/env python3
"""Rewrite legacy `#tag` inline tags to `@tag`.

    scripts/migrate-tag-syntax.py /path/to/vault --dry
    scripts/migrate-tag-syntax.py /path/to/vault

What is left alone:
  * headings (`# `, `## ` …) — the whole point of the new syntax
  * fenced code blocks and inline code spans
  * colour literals (`#fff`, `#1a2b3c`)
  * `#` that is not at the start of a line or after whitespace (URLs, `C#`)
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

HEADING = re.compile(r"^#{1,6}\s")
HEX = re.compile(r"^[0-9a-fA-F]{3,8}$")
TERMINATORS = set("、。，．！？「」『』（）【】・…—–,.:;!?\"'()[]{}<>`|\\/;:*_~=+^$%&@")


def migrate_body(body: str) -> tuple[str, list[tuple[str, str]]]:
    """Return the rewritten body and the (old, new) tags found."""
    out_lines: list[str] = []
    changed: list[tuple[str, str]] = []
    in_fence = False

    for line in body.split("\n"):
        stripped = line.lstrip()

        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            out_lines.append(line)
            continue
        if in_fence or HEADING.match(line):
            out_lines.append(line)
            continue

        result = []
        i = 0
        in_code = False
        while i < len(line):
            ch = line[i]

            if ch == "`":
                in_code = not in_code
                result.append(ch)
                i += 1
                continue

            if not in_code and ch == "#":
                at_boundary = i == 0 or line[i - 1].isspace()
                if at_boundary:
                    j = i + 1
                    while j < len(line) and not line[j].isspace() and line[j] not in TERMINATORS and line[j] != "#":
                        j += 1
                    name = line[i + 1 : j]
                    if name and not HEX.match(name):
                        result.append("@" + name)
                        changed.append(("#" + name, "@" + name))
                        i = j
                        continue
            result.append(ch)
            i += 1

        out_lines.append("".join(result))

    return "\n".join(out_lines), changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vault", type=pathlib.Path)
    parser.add_argument("--dry", action="store_true", help="only report")
    args = parser.parse_args()

    if not args.vault.is_dir():
        print(f"not a folder: {args.vault}", file=sys.stderr)
        return 1

    files = sorted(p for p in args.vault.rglob("*.md") if "assets" not in p.parts)
    total_tags = 0
    touched = 0
    samples: list[tuple[str, list[tuple[str, str]]]] = []

    for path in files:
        body = path.read_text(encoding="utf-8", errors="surrogateescape")
        new_body, changed = migrate_body(body)
        if not changed:
            continue
        touched += 1
        total_tags += len(changed)
        if len(samples) < 5:
            samples.append((path.name, changed[:6]))
        if not args.dry:
            path.write_text(new_body, encoding="utf-8", errors="surrogateescape")

    verb = "would change" if args.dry else "changed"
    print(f"{verb} {total_tags} tags in {touched} of {len(files)} files")
    for name, changes in samples:
        preview = ", ".join(f"{a}→{b}" for a, b in changes)
        print(f"  {name}: {preview}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
