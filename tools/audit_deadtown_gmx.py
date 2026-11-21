#!/usr/bin/env python3
"""Check the files referenced by the upstream Dead Town GameMaker 1 project."""
import argparse
from collections import Counter
from pathlib import Path
import xml.etree.ElementTree as ET

EXTENSIONS = {
    'Config': '.config.gmx', 'extension': '.extension.gmx',
    'sound': '.sound.gmx', 'sprite': '.sprite.gmx',
    'background': '.background.gmx', 'script': '', 'font': '.font.gmx',
    'object': '.object.gmx', 'room': '.room.gmx',
}


def audit(project_dir):
    project_dir = Path(project_dir)
    root = ET.parse(project_dir / 'deadtown.project.gmx').getroot()
    totals, missing = Counter(), []
    for node in root.iter():
        if node.tag not in EXTENSIONS or not (node.text and node.text.strip()):
            continue
        rel = node.text.strip().replace('\\', '/') + EXTENSIONS[node.tag]
        file = project_dir / rel
        totals[node.tag] += 1
        if not file.is_file():
            missing.append((node.tag, rel))
            continue
        if node.tag not in ('sprite', 'background', 'sound', 'font'):
            continue
        resource = ET.parse(file).getroot()
        tag = {'sprite': 'frame', 'background': 'data', 'sound': 'data', 'font': 'image'}[node.tag]
        for asset in resource.iter(tag):
            if not (asset.text and asset.text.strip()):
                continue
            filename = asset.text.strip().replace('\\', '/')
            asset_path = file.parent / ('audio' if node.tag == 'sound' else '') / filename
            totals[node.tag + '_data'] += 1
            if not asset_path.is_file():
                missing.append((node.tag + '_data', str(asset_path.relative_to(project_dir))))
    return totals, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project_dir', help='directory containing deadtown.project.gmx')
    args = parser.parse_args()
    totals, missing = audit(args.project_dir)
    counts = Counter(category for category, _ in missing)
    for category in sorted(totals):
        print(f'{category}: {totals[category]} references, {counts[category]} missing')
    for category, path in missing:
        print(f'MISSING {category}: {path}')
    return 1 if missing else 0


if __name__ == '__main__':
    raise SystemExit(main())
