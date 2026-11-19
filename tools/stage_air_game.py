#!/usr/bin/env python3
"""Reconstruct the reported AIR directory without modifying the source files.

The split files are byte-split parts of one ZIP archive, not ZIP's native
multi-disk format. The archive is expected to contain only m1.swf and ui.swf.
"""
import argparse
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

SWFS = ("bath.swf", "d1.swf", "fe.swf", "logo.swf", "sle.swf", "sound.swf", "top.swf", "tv.swf")
DOCS = ("color_d1.txt", "color_fe.txt", "color_m1.txt", "color_sle.txt", "color_tv.txt", "color_UI.txt", "lang.xml")
SPLIT_MEMBERS = {"m1.swf", "ui.swf"}
MAX_MEMBER_BYTES = 512 * 1024 * 1024


def stage(source: Path, destination: Path) -> None:
    source = source.resolve()
    destination = destination.resolve()
    if not source.is_dir():
        raise ValueError(f"Source directory does not exist: {source}")
    if destination.exists():
        raise ValueError(f"Destination already exists: {destination}")
    required = ("LostLife.swf", "application.xml", *SWFS, *DOCS)
    missing = [name for name in required if not (source / name).is_file()]
    if missing:
        raise ValueError("Missing source files: " + ", ".join(missing))
    parts = sorted(p for p in source.iterdir() if re.fullmatch(r"lib\.zip\.\d{3}", p.name))
    if not parts or [p.name for p in parts] != [f"lib.zip.{n:03d}" for n in range(1, len(parts) + 1)]:
        raise ValueError("Missing or non-contiguous lib.zip.001, .002, ... parts")

    destination.parent.mkdir(parents=True, exist_ok=True)
    # Stage atomically: on failure neither partial output nor extracted assets remain.
    with tempfile.TemporaryDirectory(prefix="air-stage-", dir=destination.parent) as temp:
        tmp = Path(temp)
        archive = tmp / "combined.zip"
        with archive.open("wb") as out:
            for part in parts:
                with part.open("rb") as inp:
                    shutil.copyfileobj(inp, out)
        result = tmp / "game"
        (result / "lib" / "doc").mkdir(parents=True)
        with zipfile.ZipFile(archive) as z:
            infos = z.infolist()
            if len(infos) != len(SPLIT_MEMBERS) or {i.filename for i in infos} != SPLIT_MEMBERS:
                raise ValueError("Split archive must contain exactly m1.swf and ui.swf at its root")
            for info in infos:
                if info.file_size > MAX_MEMBER_BYTES:
                    raise ValueError(f"Archive member too large: {info.filename}")
                with z.open(info) as inp, (result / "lib" / info.filename).open("wb") as out:
                    shutil.copyfileobj(inp, out)  # zipfile checks CRC while reading
        for name in SWFS:
            shutil.copy2(source / name, result / "lib" / name)
        for name in DOCS:
            shutil.copy2(source / name, result / "lib" / "doc" / name)
        shutil.copy2(source / "LostLife.swf", result / "LostLife.swf")
        # Keep the descriptor unchanged for analysis; it still references missing icons.
        shutil.copy2(source / "application.xml", result / "application.xml")
        if (source / "image.png").is_file():
            shutil.copy2(source / "image.png", result / "image.png")
        result.rename(destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Directory containing the flattened source files and ZIP parts")
    parser.add_argument("destination", type=Path, help="New output directory; must not already exist")
    args = parser.parse_args()
    try:
        stage(args.source, args.destination)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"Staging failed: {exc}", file=sys.stderr)
        return 1
    print(f"Staged files in {args.destination}. The descriptor's missing icons still need attention.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
