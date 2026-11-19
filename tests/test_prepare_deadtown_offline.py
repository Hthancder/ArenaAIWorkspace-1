import hashlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from tools.prepare_deadtown_offline import PatchError, prepare, replace_in_strings, replace_once


class OfflinePatchUnitTests(unittest.TestCase):
    def test_replace_once_requires_exactly_one_match(self):
        self.assertEqual(replace_once('a b a', ' b ', ' c ', 'test'), 'a c a')
        for value in ('aaa', 'a a'):
            with self.assertRaises(PatchError):
                replace_once(value, 'a', 'z', 'test')

    def test_replace_in_strings_targets_action_text(self):
        tree = ET.ElementTree(ET.fromstring('<object><string>a &lt; b</string></object>'))
        replace_in_strings(tree, 'a < b', 'true', 'test')
        self.assertEqual(tree.find('.//string').text, 'true')

    def test_refuses_existing_output_without_touching_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, output = Path(tmp) / 'src', Path(tmp) / 'out'
            source.mkdir()
            output.mkdir()
            (source / 'deadtown.project.gmx').write_text('<assets/>')
            (output / 'keep').write_text('keep')
            with self.assertRaises(PatchError):
                prepare(source, output)
            self.assertEqual((output / 'keep').read_text(), 'keep')


STAGED = Path(__file__).resolve().parents[1] / '.cache/deadtown-staged'


@unittest.skipUnless((STAGED / 'deadtown.project.gmx').exists(), 'requires staged upstream project')
class OfflineRealProjectTests(unittest.TestCase):
    def test_offline_patch_and_source_integrity(self):
        source = STAGED / 'objects/sys_global.object.gmx'
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / 'offline'
            self.assertEqual(prepare(STAGED, result), 18)
            self.assertNotIn('push_get_first_local_notification', (result / 'scripts/push_clear.gml').read_text())
            self.assertNotIn('push_local_notification', (result / 'scripts/push_push.gml').read_text())
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
            tree = ET.parse(result / 'deadtown.project.gmx')
            self.assertEqual(list(tree.find('NewExtensions')), [])
            config = ET.parse(result / 'Configs/Default.config.gmx')
            self.assertEqual(config.findtext('.//option_android_google_play'), '0')
            obj = ET.parse(result / 'objects/sys_global.object.gmx')
            actions = '\n'.join(n.text or '' for n in obj.iter('string'))
            self.assertLess(actions.index('iap_item_load()'), actions.index('offline_i = 5'))
            self.assertIn('offline_i <= 13', actions)
            self.assertNotIn('unity_ads_init(', actions)
            self.assertNotIn('iap_purchase_details(', actions)
            self.assertIn('= 0 // offline: free shop', (result / 'scripts/shop_db_add.gml').read_text())
            self.assertEqual((result / 'sound/audio/snd_item_get.ogg').read_bytes(),
                             (STAGED / 'sound/audio/snd_item_get.ogg').read_bytes())
            for xml_file in result.rglob('*.gmx'):
                ET.parse(xml_file)


if __name__ == '__main__':
    unittest.main()
