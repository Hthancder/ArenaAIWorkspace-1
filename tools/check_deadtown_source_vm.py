#!/usr/bin/env python3
"""Summarize a disposable VM compile and native-resource comparison.

The probe removes unresolved native code and can swallow VM errors. This tool
makes those gaps visible; its successful execution is NOT a game release gate,
GameMaker compilation, original gameplay or iPhone validation.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import zipfile

try:
    from tools.deadtown_ios_compare import png_payloads, sprite_layout
    from tools.deadtown_native_inventory import resource_names
    from tools.deadtown_native_lang import APK_SHA256
    from tools.recover_deadtown_audio import read_zip_member
except ModuleNotFoundError:
    from deadtown_ios_compare import png_payloads, sprite_layout
    from deadtown_native_inventory import resource_names
    from deadtown_native_lang import APK_SHA256
    from recover_deadtown_audio import read_zip_member

GAME_DATA_SHA256 = '0900da067462bd48040da6e217a86e2d5411397b05f07d55d13c58440b82a7b8'


def one(pattern, text, label):
    values = re.findall(pattern, text, flags=re.MULTILINE)
    if len(values) != 1:
        raise ValueError(f'expected one {label} marker; found {len(values)}')
    return values[0]


def parse_probe(text, expected_scripts, expected_events):
    scripts, missing_scripts, extra_scripts = map(int, one(
        r'PROBE: attempting (\d+) staged offline source scripts; APK scripts absent from source=(\d+), source scripts absent from APK=(\d+)',
        text, 'source-script'))
    events = int(one(r'PROBE: compiling (\d+) translated event bodies;', text, 'event-count'))
    compile_success = one(r'PROBE: compile_success=(True|False),', text, 'compile')
    linked, skipped = map(int, one(r'PROBE: linked (\d+) events to matching APK objects; skipped (\d+) missing objects or collision targets', text, 'linked'))
    cleared = int(one(r'PROBE: removed (\d+) unresolved native code IDs;', text, 'cleared'))
    if scripts != expected_scripts or events != expected_events or linked + skipped != events:
        raise ValueError('probe counts differ from current source or do not add up')
    if compile_success != 'True':
        raise ValueError('source probe reported compilation failure')
    return {'source_script_files_compiled': scripts, 'native_scripts_absent_from_source_by_name': missing_scripts,
            'source_scripts_absent_from_native_by_name': extra_scripts, 'translated_event_bodies_compiled': events,
            'events_linked': linked, 'event_links_skipped': skipped, 'native_code_references_cleared': cleared}


def summarize_runtime(log, expected_room):
    lines = log.splitlines()
    if not any(f'[room] -> {expected_room}' in line for line in lines):
        raise ValueError(f'expected room not observed: {expected_room}')
    # Runner prints some messages only once, so these are logged entries, not
    # counts of actual failures in all execution paths.
    errors = [s for s in lines if '[gml] error in ' in s or '[gml] internal error in ' in s or '[vm]' in s]
    unknown = [s for s in lines if 'call to unknown function ' in s]
    warnings = [s for s in lines if '[gml]' in s and s not in errors and s not in unknown]
    counts = Counter(errors)
    return {'expected_room_observed': expected_room, 'diagnostic_lines': len(errors),
            'distinct_diagnostics': [{'line': msg[:1200], 'occurrences': n} for msg, n in counts.most_common(15)],
            'unknown_function_lines': len(unknown), 'other_gml_lines': len(warnings),
            'limitations': 'Headless forced scenario only. Logged entries may be suppressed/deduplicated; '
                           'zero logs cannot prove error-free gameplay.'}


def compare_resources(apk, candidate):
    apk = Path(apk)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA256:
        raise ValueError('unexpected APK SHA-256')
    with zipfile.ZipFile(apk) as archive:
        original = read_zip_member(archive, 'assets/game.droid')
    if hashlib.sha256(original).hexdigest() != GAME_DATA_SHA256:
        raise ValueError('unexpected APK game data SHA-256')
    probe = Path(candidate).read_bytes()
    resources = {}
    for kind in (b'SPRT', b'OBJT', b'ROOM', b'SCPT'):
        source, dest = resource_names(original, kind), resource_names(probe, kind)
        if len(set(source)) != len(source) or len(set(dest)) != len(dest):
            raise ValueError(f'duplicate resource name in {kind.decode()}')
        resources[kind.decode()] = {'apk_count': len(source), 'probe_count': len(dest),
                                    'same_names_in_order': source == dest}
    a, b = sprite_layout(original), sprite_layout(probe)
    if set(a) != set(b):
        raise ValueError('sprite resource names changed in probe')
    changed = [name for name in a if a[name] != b[name]]
    orig_png, new_png = png_payloads(original), png_payloads(probe)
    result = {'resource_names': resources, 'sprite_layout_differences': changed,
              'texture_png_counts': [len(orig_png), len(new_png)],
              'texture_pngs_same_in_order': orig_png == new_png,
              'probe_sha256': hashlib.sha256(probe).hexdigest()}
    # This probe is deliberately designed to keep original sprites, objects,
    # and rooms. Never report a changed asset as proof of resource preservation.
    if not all(resources[k]['same_names_in_order'] for k in ('SPRT', 'OBJT', 'ROOM')) or changed or orig_png != new_png:
        raise ValueError('expected original resource preservation did not hold')
    return result


def report(apk, candidate, project, events, compile_log, boot_log, play_log):
    event_list = json.loads(Path(events).read_text(encoding='utf-8'))
    if not isinstance(event_list, list):
        raise ValueError('unexpected source events')
    scripts = list((Path(project) / 'scripts').glob('*.gml'))
    if not scripts or not event_list:
        raise ValueError('source scripts or events missing')
    return {'compile': parse_probe(Path(compile_log).read_text(errors='replace'), len(scripts), len(event_list)),
            'resources': compare_resources(apk, candidate),
            'boot': summarize_runtime(Path(boot_log).read_text(errors='replace'), 'rom_lobby'),
            'forced_play': summarize_runtime(Path(play_log).read_text(errors='replace'), 'rom_play'),
            'release_ready': False,
            'limitations': 'Disposable YYC-to-VM experiment. Old native code and missing links are removed; '
                           'sprites/masks/textures come from the APK, NOT the editable source PNG overrides. '
                           'No GameMaker compiler, original runtime, iOS, touch or complete gameplay is tested.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('apk', 'candidate', 'project', 'events', 'compile_log', 'boot_log', 'play_log'):
        p.add_argument(arg, type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    result = report(args.apk, args.candidate, args.project, args.events, args.compile_log, args.boot_log, args.play_log)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('SOURCE_VM_DIAGNOSTIC:', json.dumps({'compile': result['compile'],
          'resources': result['resources'], 'boot': result['boot'], 'forced_play': result['forced_play'],
          'release_ready': False}, ensure_ascii=False, separators=(',', ':')))


if __name__ == '__main__':
    main()
