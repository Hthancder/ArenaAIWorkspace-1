#!/usr/bin/env python3
"""Stage the original Dead Town GMX project without altering the upstream copy."""
import argparse
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

if __package__:
    from .audit_deadtown_gmx import audit
else:
    from audit_deadtown_gmx import audit


def stage(source, destination, audio_dir=None):
    source, destination = Path(source), Path(destination)
    if not (source / 'deadtown.project.gmx').is_file():
        raise ValueError('source must be the directory containing deadtown.project.gmx')
    if destination.exists():
        raise ValueError('destination already exists; refusing to overwrite it')
    if source.resolve() in destination.resolve().parents:
        raise ValueError('destination must not be inside the source project')
    if audio_dir is not None and not Path(audio_dir).is_dir():
        raise ValueError('audio directory does not exist')

    # Copy only the project, never the upstream git checkout or adjacent assets.
    shutil.copytree(source, destination)
    copied = 0
    if audio_dir is not None:
        audio_dir = Path(audio_dir)
        for descriptor in (destination / 'sound').glob('*.sound.gmx'):
            name = ET.parse(descriptor).findtext('data')
            if not name or Path(name).name != name or '\\' in name:
                continue
            input_file = audio_dir / name
            output_file = destination / 'sound' / 'audio' / name
            if input_file.is_file() and not output_file.exists():
                output_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(input_file, output_file)
                copied += 1
    totals, missing = audit(destination)
    return copied, totals, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='upstream deadtown.gmx directory')
    parser.add_argument('destination', help='new output directory')
    parser.add_argument('--audio-dir', help='directory containing original audio files with their original names')
    args = parser.parse_args()
    try:
        copied, totals, missing = stage(args.source, args.destination, args.audio_dir)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 2
    print(f'Staged {args.destination}; copied {copied} matching audio files.')
    for category in sorted(totals):
        count = sum(kind == category for kind, _ in missing)
        print(f'{category}: {totals[category]} references, {count} missing')
    if missing:
        print('Project remains incomplete; run audit_deadtown_gmx.py for the missing paths.')
        return 1
    print('Referenced files found. This does not establish build compatibility.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
