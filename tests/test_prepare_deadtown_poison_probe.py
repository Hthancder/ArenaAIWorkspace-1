import copy
import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import xml.etree.ElementTree as ET

from tools.prepare_deadtown_offline import PatchError
from tools.prepare_deadtown_poison_probe import EXPECTED, NOTICE, prepare, replace_use_rows

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get('DEADTOWN_TEST_OFFLINE', ROOT / '.cache/deadtown-offline'))
APK = Path(os.environ.get('DEADTOWN_TEST_APK', ROOT / '.cache/deadtown-original.apk'))
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


def row(name, duration=0):
    values = [name, 0, 'description', 0, 0, 0, 0, 0, -1, duration]
    types = ['string', 'number', 'string'] + ['number'] * 7
    return {'arguments': [{'type': kind, 'value': value} for kind, value in zip(types, values)]}


class PoisonProbeUnitTests(unittest.TestCase):
    def test_rewrites_exact_order_only(self):
        names = [f'Food{i}' for i in range(20)]
        source = '\n'.join(f'db_use_add("{name}",spr_noone,"description",0,0,0,0,0,-1)' for name in names)
        candidates = [row(name) for name in names] + [row('Gas mask', 3), row('Splint')]
        result = replace_use_rows('before\n' + source + '\nafter', candidates)
        self.assertIn('db_use_add("Gas mask",spr_noone,"description",0,0,0,0,0,-1,3)', result)
        self.assertTrue(result.startswith('before\n') and result.endswith('\nafter'))
        candidates[1], candidates[2] = candidates[2], candidates[1]
        with self.assertRaisesRegex(PatchError, 'ordering'):
            replace_use_rows(source, candidates)

    def test_rejects_injection_and_noncontiguous_rows(self):
        names = [f'Food{i}' for i in range(20)]
        source = '\n'.join(f'db_use_add("{name}",spr_noone,"description",0,0,0,0,0,-1)' for name in names)
        candidates = [row(name) for name in names] + [row('Gas mask', 3), row('Splint')]
        bad = copy.deepcopy(candidates)
        bad[0]['arguments'][2]['value'] = 'bad"code'
        with self.assertRaisesRegex(PatchError, 'literal'):
            replace_use_rows(source, bad)
        with self.assertRaisesRegex(PatchError, 'contiguous'):
            replace_use_rows(source.replace('\ndb_use_add("Food1"', '\n// extra\ndb_use_add("Food1"'), candidates)

    def test_never_overwrites_and_refuses_nested_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'
            source.mkdir()
            (source / 'deadtown.project.gmx').write_text('original')
            output = Path(tmp) / 'existing'
            output.mkdir()
            (output / 'keep').write_text('preserve')
            with self.assertRaisesRegex(PatchError, 'already exists'):
                prepare(source, 'unused.apk', output)
            self.assertEqual((output / 'keep').read_text(), 'preserve')
            with self.assertRaisesRegex(PatchError, 'must not contain'):
                prepare(source, 'unused.apk', source / 'nested')

    def test_failed_copy_cleans_only_the_new_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'
            source.mkdir()
            (source / 'deadtown.project.gmx').write_text('original')
            output = Path(tmp) / 'new'
            with mock.patch('tools.prepare_deadtown_poison_probe.plan', return_value={}), \
                 mock.patch('tools.prepare_deadtown_poison_probe.shutil.copytree', side_effect=OSError('copy failed')):
                with self.assertRaisesRegex(OSError, 'copy failed'):
                    prepare(source, 'unused.apk', output)
            self.assertFalse(output.exists())
            self.assertEqual((source / 'deadtown.project.gmx').read_text(), 'original')


@unittest.skipUnless(SOURCE.is_dir() and APK.is_file() and HAS_RE, 'requires staged offline project and pinned APK')
class PoisonProbeIntegrationTests(unittest.TestCase):
    def test_isolated_probe_and_unchanged_source(self):
        before = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in EXPECTED}
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'probe'
            self.assertEqual(prepare(SOURCE, APK, output), 7)
            self.assertEqual((output / 'RESEARCH-PROBE-NOT-A-RELEASE.txt').read_text(), NOTICE)
            obj = ET.parse(output / 'objects/sys_global.object.gmx')
            action = next(node.text for node in obj.iter('string') if 'db_use_add(' in (node.text or ''))
            self.assertEqual(action.count('db_use_add('), 22)
            self.assertIn('db_use_add("Gas mask",spr_noone,"Mask to protect player from poison",0,0,0,0,0,-1,3)', action)
            self.assertIn('buff_poison_protect', (output / 'scripts/item_use.gml').read_text())
            self.assertIn('buffpoisonprotect', (output / 'scripts/game_save_protect.gml').read_text())
            self.assertIn('buffpoisonprotect', (output / 'scripts/game_load_protect.gml').read_text())
            player = ET.parse(output / 'objects/obj_player.object.gmx')
            texts = '\n'.join(node.text or '' for node in player.iter('string'))
            self.assertIn('buff_poison_hurt = hp_max/4500', texts)
            self.assertIn('buff_poison_protect -= 1', texts)
        self.assertEqual(before, {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in EXPECTED})


if __name__ == '__main__':
    unittest.main()
