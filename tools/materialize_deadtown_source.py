#!/usr/bin/env python3
"""Materialize the editable, explicitly incomplete Dead Town source workbench.

This does not build an IPA or restore native YYC game code. It refuses changed
inputs and existing destinations. Editable GMX/GML lives in the repository;
original assets are copied from pinned user-supplied inputs into a new output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

try:
    from tools.audit_deadtown_gmx import audit
    from tools.deadtown_native_inventory import compare
    from tools.deadtown_native_lang import APK_SHA256
    from tools.deadtown_sprite_metadata import compare as compare_sprites
    from tools.prepare_deadtown_offline import prepare
    from tools.recover_deadtown_audio import apply, extract
    from tools.stage_deadtown_gmx import stage
except ModuleNotFoundError:
    from audit_deadtown_gmx import audit
    from deadtown_native_inventory import compare
    from deadtown_native_lang import APK_SHA256
    from deadtown_sprite_metadata import compare as compare_sprites
    from prepare_deadtown_offline import prepare
    from recover_deadtown_audio import apply, extract
    from stage_deadtown_gmx import stage

UPSTREAM_COMMIT = '5e3d798f914c8cd3b066c8289323005d63111f37'
PROJECT_TREE_SHA256 = '2a50b5a0bd7da1e844c8b79017dbb3bd6472e49c536663e477967d04d0d03886'
SOURCE_EXTENSIONS = {'.gmx', '.gml'}
FORBIDDEN_EXTENSIONS = {'.p12', '.pfx', '.key', '.pem', '.mobileprovision'}
DEFAULT_SOURCE = Path(__file__).resolve().parents[1] / 'deadtown-source'


def files_under(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f'not a real directory: {root}')
    result = []
    for p in sorted(root.rglob('*'), key=lambda x: x.relative_to(root).as_posix()):
        if p.is_symlink():
            raise ValueError(f'symlink rejected: {p}')
        if p.is_file():
            result.append(p)
        elif not p.is_dir():
            raise ValueError(f'unsupported file: {p}')
    return result


def tree_digest(root):
    root = Path(root)
    digest = hashlib.sha256()
    files = files_under(root)
    for file in files:
        name = file.relative_to(root).as_posix().encode('utf-8')
        digest.update(len(name).to_bytes(4, 'big'))
        digest.update(name)
        digest.update(hashlib.sha256(file.read_bytes()).digest())
    return len(files), digest.hexdigest()


def validate_inputs(upstream, apk, source, output):
    upstream, apk, source, output = map(Path, (upstream, apk, source, output))
    if output.exists() or output.is_symlink():
        raise ValueError('destination exists; never overwrite an existing workspace')
    if not output.parent.is_dir():
        raise ValueError('destination parent must already exist')
    if output.resolve().is_relative_to(upstream.resolve()) or output.resolve().is_relative_to(source.resolve()):
        raise ValueError('destination cannot be inside either source directory')
    if tree_digest(upstream) != (2030, PROJECT_TREE_SHA256):
        raise ValueError('upstream GMX tree does not match pinned revision')
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('APK SHA-256 does not match pinned input')
    overlay = source / 'project'
    files = files_under(overlay)
    if not files or not (overlay / 'deadtown.project.gmx').is_file():
        raise ValueError('editable source project missing')
    if any(f.suffix.lower() not in SOURCE_EXTENSIONS for f in files):
        raise ValueError('editable project may contain GMX and GML files only')
    assets = source / 'assets'
    if assets.exists() or assets.is_symlink():
        for f in files_under(assets):
            if f.suffix.lower() in SOURCE_EXTENSIONS | FORBIDDEN_EXTENSIONS or '.git' in f.relative_to(assets).parts:
                raise ValueError(f'forbidden asset override: {f}')


def materialize(upstream, apk, source, output):
    upstream, apk, source, output = map(Path, (upstream, apk, source, output))
    validate_inputs(upstream, apk, source, output)
    output.mkdir()  # exclusive ownership; failures retain the directory for inspection
    (output / 'INCOMPLETE.txt').write_text('INCOMPLETE: preparation has not finished; never use as a release.\n')
    with tempfile.TemporaryDirectory(prefix='.prepare-', dir=output) as temp:
        temp = Path(temp)
        extract(apk, temp / 'audio')
        stage(upstream, temp / 'staged')
        audio_count = apply(temp / 'staged', temp / 'audio')
        prepare(temp / 'staged', temp / 'offline')
        project = temp / 'offline'
        # Offline project no longer declares the legacy ad extension. Do not
        # carry its bundled extension archive into the editable game output.
        ad_archive = project / 'datafiles' / 'UnityAdsExt.gmez'
        if ad_archive.is_file():
            ad_archive.unlink()
        # The editable tree is authoritative for all GMX/GML; deleted source
        # files must not silently reappear from the old upstream copy.
        for file in files_under(project):
            if file.suffix.lower() in SOURCE_EXTENSIONS | FORBIDDEN_EXTENSIONS:
                file.unlink()
        overlay = source / 'project'
        for file in files_under(overlay):
            destination = project / file.relative_to(overlay)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, destination)
        assets = source / 'assets'
        if assets.is_dir():
            for file in files_under(assets):
                destination = project / file.relative_to(assets)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, destination)
        totals, missing = audit(project)
        report = compare(apk, project)
        sprites = compare_sprites(apk, project)
        if report['apk_sha256'] != APK_SHA256:
            raise ValueError('comparison unexpectedly used different APK')
        summary = report['comparison']['project_declared']
        status = {'state': 'INCOMPLETE_NOT_FOR_RELEASE', 'upstream_commit': UPSTREAM_COMMIT,
                  'upstream_tree_sha256': PROJECT_TREE_SHA256, 'apk_sha256': APK_SHA256,
                  'audio_descriptors_populated_without_transcoding': audio_count,
                  'missing_referenced_files': [{'type': kind, 'path': path} for kind, path in missing],
                  'resource_reference_counts': dict(totals),
                  'native_scripts_missing_by_name': len(summary['native_scripts_missing_in_source']),
                  'native_objects_missing_by_name': len(summary['native_objects_missing_in_source']),
                  'native_events_missing_by_key': len(summary['native_event_keys_missing_in_source']),
                  'native_sprites_missing_by_name': len(sprites['apk_only']),
                  'native_backgrounds_missing_by_name': len(report['native_backgrounds_missing_by_name']),
                  'native_rooms_missing_by_name': len(report['native_rooms_missing_by_name']),
                  'native_sounds_missing_by_name': len(report['native_sounds_missing_by_name']),
                  'shared_sprites_differing_metadata': sprites['differing_metadata'],
                  'limitations': 'Names and file existence do not establish matching behavior or a successful build. '
                                 'Native YYC logic is not automatically recovered. No iPhone test or IPA is produced.'}
        (output / 'comparison.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        (output / 'sprite-metadata.json').write_text(json.dumps(sprites, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        (output / 'status.json').write_text(json.dumps(status, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        shutil.move(str(project), str(output / 'project'))
    (output / 'INCOMPLETE.txt').write_text(
        'INCOMPLETE: older GMX baseline, not original 1.4.2 source and not a release.\n'
        'See status.json and comparison.json. No IPA was built.\n', encoding='utf-8')
    return status


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('upstream', type=Path, help='pinned upstream deadtown.gmx directory')
    p.add_argument('apk', type=Path, help='pinned original APK')
    p.add_argument('output', type=Path, help='new destination directory')
    p.add_argument('--source', type=Path, default=DEFAULT_SOURCE, help='editable source and optional assets overrides')
    args = p.parse_args()
    try:
        status = materialize(args.upstream, args.apk, args.source, args.output)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as exc:
        print('ERROR:', exc, file=sys.stderr)
        return 2
    print('SOURCE_WORKBENCH:', json.dumps(status, ensure_ascii=False, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
