import tempfile
import unittest
from pathlib import Path

from tools.deadtown_sprite_order_evidence import analyze_order, compare, declared_sprites

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
PROJECT = ROOT / 'deadtown-source/project'


class SpriteOrderUnitTests(unittest.TestCase):
    def test_differences_and_inversions(self):
        result = analyze_order(['a', 'b', 'c', 'd'], ['b', 'a', 'c', 'extra'])
        self.assertEqual(result['same_numeric_ordinal'], 1)
        self.assertEqual(result['different_common_rank'], 2)
        self.assertEqual(result['relative_order_inversions'], 1)
        self.assertEqual(result['missing_from_gmx'], ['d'])
        self.assertEqual(result['only_in_gmx'], ['extra'])
        self.assertEqual(result['shared'][0]['apk_sprite_id'], 1)
        self.assertEqual(result['shared'][0]['gmx_declared_ordinal'], 0)

    def test_bad_names_and_paths_fail(self):
        for native, declared in (([], ['a']), (['a', 'a'], ['a']), (['a'], ['a', 'a'])):
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                analyze_order(native, declared)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'deadtown.project.gmx'
            path.write_text('<assets><sprites><sprite>sprites\\good</sprite>'
                            '<sprites><sprite>sprites\\other</sprite></sprites></sprites></assets>')
            self.assertEqual(declared_sprites(tmp), ['good', 'other'])
            path.write_text('<assets><sprites><sprite>sprites\\..\\bad</sprite></sprites></assets>')
            with self.assertRaisesRegex(ValueError, 'path'):
                declared_sprites(tmp)

    def test_bad_apk_fails_before_parsing(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.apk'
            path.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'APK SHA-256'):
                compare(path, PROJECT)


@unittest.skipUnless(APK.is_file() and PROJECT.is_dir(), 'requires pinned APK and source')
class SpriteOrderIntegrationTests(unittest.TestCase):
    def test_real_inventory_and_reference_anchor(self):
        result = compare(APK, PROJECT)
        self.assertEqual(result['native_sprites'], 402)
        player = next(r for r in result['shared'] if r['name'] == 'spr_player')
        self.assertEqual(player['apk_sprite_id'], 182)
        self.assertEqual(result['gmx_declared_sprites'], result['shared_sprites'] + len(result['only_in_gmx']))
        self.assertEqual(result['native_sprites'], result['shared_sprites'] + len(result['missing_from_gmx']))


if __name__ == '__main__':
    unittest.main()
