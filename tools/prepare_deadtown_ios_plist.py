#!/usr/bin/env python3
"""Prepare a landscape-only plist for the experimental Dead Town IPA.

The iOS runner previously started its SDL window with portrait dimensions,
then rotated the screen, leaving the drawable clipped. Locking this game to
landscape from launch avoids that orientation change; device testing is needed.
"""
import argparse
import plistlib
from pathlib import Path

LANDSCAPE = ['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
BUNDLE_ID = 'org.gmrunner.deadtown.experimental'


def prepare(info):
    if info.get('MinimumOSVersion') != '15.0':
        raise ValueError('expected a runner targeting iOS 15.0')
    if not isinstance(info.get('CFBundleExecutable'), str) or not info['CFBundleExecutable']:
        raise ValueError('missing executable')
    result = dict(info)
    result['CFBundleIdentifier'] = BUNDLE_ID
    result['CFBundleDisplayName'] = 'Dead Town Test'
    result['UISupportedInterfaceOrientations'] = list(LANDSCAPE)
    result['UISupportedInterfaceOrientations~ipad'] = list(LANDSCAPE)
    result['UIRequiresFullScreen'] = True
    # This is packaged from the first runner, so increment the original build
    # number to distinguish it while retaining the same bundle ID and saves.
    version = str(result.get('CFBundleVersion', '1'))
    if not version.isdigit():
        raise ValueError(f'unexpected build version: {version}')
    result['CFBundleVersion'] = str(int(version) + 1)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plist', type=Path)
    args = parser.parse_args()
    info = plistlib.loads(args.plist.read_bytes())
    args.plist.write_bytes(plistlib.dumps(prepare(info), fmt=plistlib.FMT_BINARY, sort_keys=False))


if __name__ == '__main__':
    main()
