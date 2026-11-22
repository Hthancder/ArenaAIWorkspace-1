import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_event_probe import extract_events
from tools.deadtown_inventory_keys_evidence import inspect, verify_source
from tools.deadtown_inventory_keys_vm_probe import MARKERS, check, instrument

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT/'deadtown-source/project'
APK = ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    DEPS = True
except ImportError:
    DEPS = False


class InventoryKeysTest(unittest.TestCase):
    def test_source_mutation(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'objects'; path.mkdir()
            target=path/'sys_UI.object.gmx'; shutil.copy(PROJECT/'objects/sys_UI.object.gmx',target)
            original=target.read_text(encoding='utf-8')
            for old,new in [('backpack_order_close = 0\n    backpack_close()', 'backpack_close()'),
                            ('if pause &gt; 0.5','if pause &gt; 1'),
                            ('if backpack_open != 0','if backpack_open == 0'),
                            ('eventtype="9" enumb="32"','eventtype="9" enumb="33"')]:
                self.assertIn(old,original); target.write_text(original.replace(old,new),encoding='utf-8')
                with self.assertRaises(ValueError): verify_source(Path(tmp))
                target.write_text(original,encoding='utf-8')

    def test_probe(self):
        events=extract_events(PROJECT)
        instrument(events, PROJECT)
        self.assertEqual(check('\n'.join(MARKERS)),len(MARKERS))
        with self.assertRaises(ValueError): check('\n'.join(MARKERS[:-1]))

    @unittest.skipUnless(DEPS and APK.is_file(),'requires pinned APK and analysis dependencies')
    def test_arm(self):
        report=inspect(APK)
        self.assertEqual(report['slot_aliases']['0x25c'],'backpack_order_close')

if __name__=='__main__': unittest.main()
