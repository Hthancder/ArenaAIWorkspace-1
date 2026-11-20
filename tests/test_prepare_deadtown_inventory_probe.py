import hashlib
import os
from pathlib import Path
import tempfile
import unittest

from tools.prepare_deadtown_inventory_probe import EXPECTED, prepare, rewrite
from tools.prepare_deadtown_offline import PatchError

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get('DEADTOWN_TEST_OFFLINE', ROOT / '.cache/deadtown-offline'))


class InventoryProbeTests(unittest.TestCase):
    def test_rewrite_validates_counts_and_rejects_unknown(self):
        text = 'target_inven[? pointer] += item_number;\n'
        self.assertEqual(rewrite(text, 'item_get'),
                         'ds_map_replace(target_inven,pointer,ds_map_find_value(target_inven,pointer) + item_number);\n')
        for value in (text + text, text.replace('pointer', 'other'), text + '// [? unexpected\n'):
            with self.assertRaises(PatchError):
                rewrite(value, 'item_get')
        with self.assertRaises(PatchError):
            rewrite(text, 'unknown')

    def test_refuses_existing_or_nested_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            existing = root / 'existing'
            existing.mkdir()
            (existing / 'keep').write_text('safe')
            with self.assertRaisesRegex(PatchError, 'already exists'):
                prepare(root / 'source', existing)
            self.assertEqual((existing / 'keep').read_text(), 'safe')
            with self.assertRaisesRegex(PatchError, 'contain'):
                prepare(root, root / 'nested')

    def test_wrong_source_fails_without_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'source/scripts').mkdir(parents=True)
            (root / 'source/scripts/item_get.gml').write_text('unexpected')
            with self.assertRaisesRegex(PatchError, 'unexpected source'):
                prepare(root / 'source', root / 'out')
            self.assertFalse((root / 'out').exists())

    @unittest.skipUnless(SOURCE.is_dir(), 'requires pinned offline source')
    def test_pinned_source_is_unchanged(self):
        before = {name: hashlib.sha256((SOURCE / 'scripts' / (name + '.gml')).read_bytes()).hexdigest()
                  for name in EXPECTED}
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'probe'
            self.assertEqual(prepare(SOURCE, output), 4)
            for name in EXPECTED:
                text = (output / (name + '.gml')).read_text()
                self.assertNotIn('[?', text)
                self.assertIn('ds_map_replace(', text)
        self.assertEqual(before, {name: hashlib.sha256((SOURCE / 'scripts' / (name + '.gml')).read_bytes()).hexdigest()
                                  for name in EXPECTED})


if __name__ == '__main__':
    unittest.main()
