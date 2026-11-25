#!/usr/bin/env python3
"""Move attachments into assets/ and rewrite legacy `![[name]]` embeds.

    scripts/migrate-images.py /path/to/vault --dry
    scripts/migrate-images.py /path/to/vault

* images move to `assets/` and are renamed to `YYYY-MM-DD-HHMMSS.ext` (taken from the
  original name when it carries a date, otherwise from the file's modification time)
* `![[name.png]]` and `![[name.png|300]]` become `![alt](assets/name.png)`; the size
  suffix is dropped, Markdown has no portable equivalent
* links are percent-encoded nowhere: the new names are ASCII with no spaces
"""

from __future__ import annotations

import argparse
import datetime
import pathlib
import re
import shutil
import sys

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"}
SCREENSHOT = re.compile(
    r"^Screenshot (\d{4})-(\d{2})-(\d{2}) at (\d{1,2})\.(\d{2})\.(\d{2}) (AM|PM)$"
)
PASTED = re.compile(r"^Pasted image (\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$")


def target_name(path: pathlib.Path) -> str:
    stem = path.stem
    m = SCREENSHOT.match(stem)
    if m:
        year, month, day, hour, minute, second, meridiem = m.groups()
        hour = int(hour) % 12 + (12 if meridiem == "PM" else 0)
        return f"{year}-{month}-{day}-{hour:02d}{minute}{second}{path.suffix.lower()}"
    m = PASTED.match(stem)
    if m:
        year, month, day, hour, minute, second = m.groups()
        return f"{year}-{month}-{day}-{hour}{minute}{second}{path.suffix.lower()}"
    stamp = datetime.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d-%H%M%S")
    return f"{stamp}{path.suffix.lower()}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vault", type=pathlib.Path)
    parser.add_argument("--dry", action="store_true")
    args = parser.parse_args()

    root: pathlib.Path = args.vault
    if not root.is_dir():
        print(f"not a folder: {root}", file=sys.stderr)
        return 1

    assets = root / "assets"
    images = [p for p in root.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXT]
    moved: dict[str, str] = {}
    for image in images:
        name = target_name(image)
        destination = assets / name
        n = 2
        while destination.exists():
            destination = assets / f"{destination.stem}-{n}{destination.suffix}"
            n += 1
        moved[image.name] = destination.name
        print(f"{'[dry] ' if args.dry else ''}move {image.name!r} -> assets/{destination.name}")
        if not args.dry:
            assets.mkdir(exist_ok=True)
            shutil.move(str(image), str(destination))

    files = sorted(p for p in root.rglob("*.md") if "assets" not in p.parts)
    edited = 0
    replaced = 0
    for path in files:
        body = path.read_text(encoding="utf-8", errors="surrogateescape")
        out = body
        for old, new in moved.items():
            pattern = re.compile(r"!\[\[" + re.escape(old) + r"(\|[^\]]*)?\]\]")
            out, count = pattern.subn(f"![]({'assets/' + new})", out)
            replaced += count
        if out != body:
            edited += 1
            if not args.dry:
                path.write_text(out, encoding="utf-8", errors="surrogateescape")

    leftover = [p.name for p in files if "[[" in p.read_text(encoding="utf-8", errors="surrogateescape")]
    print(f"{'would replace' if args.dry else 'replaced'} {replaced} embeds in {edited} files")
    print(f"leftover wiki embeds: {leftover or 'none'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
