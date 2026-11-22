from pathlib import Path
import shutil
import tempfile
import unittest

from tools.deadtown_boss2_distance_evidence import CANDIDATE, inspect, verify_source
from tools.deadtown_boss2_distance_vm_probe import MARKER, check, instrument

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT/'deadtown-source/project'
APK = ROOT/'.cache/deadtown-original.apk'
try:
    import capstone
    import elftools
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


def event(obj, typ, sub, text='original();'):
    return {'object': obj, 'attributes': {'eventtype': typ, 'enumb': sub}, 'gml': text}


class BossDistanceTests(unittest.TestCase):
    def test_source_and_mutations(self):
        verify_source(PROJECT)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            shutil.copy(PROJECT/'deadtown.project.gmx', dest)
            (dest/'objects').mkdir()
            p = dest/'objects/obj_boss2.object.gmx'
            shutil.copy(PROJECT/'objects/obj_boss2.object.gmx', p)
            parent = dest/'objects/par_boss.object.gmx'
            shutil.copy(PROJECT/'objects/par_boss.object.gmx', parent)
            original = p.read_text()
            for old, new in ((' &gt; 8000', ' &gt; 800'),
                             ('point_distance(x,y,obj_player.x,obj_player.y)', 'point_distance(x,y,obj_player.x,obj_player.x)'),
                             ('eventtype="3" enumb="2"', 'eventtype="3" enumb="1"'),
                             ('instance_destroy()\n}\n</string>\n          </argument>\n        </arguments>\n      </action>\n    </event>\n  </events>',
                              'instance_deactivate_object()\n}\n</string>\n          </argument>\n        </arguments>\n      </action>\n    </event>\n  </events>')):
                self.assertIn(old, original)
                p.write_text(original.replace(old, new, 1))
                with self.assertRaises(ValueError):
                    verify_source(dest)
                p.write_text(original)
            parent_text = parent.read_text()
            parent.write_text(parent_text.replace('The boss fled', 'changed'))
            with self.assertRaises(ValueError):
                verify_source(dest)

    def test_probe_and_markers(self):
        events = [event('sys_global', '0', '0'), event('sys_global', '3', '0'),
                  event('obj_boss2', '3', '2', '{\n'+CANDIDATE+'\n}')]
        for obj, items in (('obj_player', [('0','0'), ('1','0'), ('3','0'), ('3','1'), ('3','2')]),
                           ('obj_boss2', [('0','0'), ('1','0'), ('3','0')])):
            events.extend(event(obj, typ, sub) for typ, sub in items)
        instrument(events, PROJECT)
        self.assertIn('8001', events[0]['gml'])
        self.assertEqual(check(MARKER), 1)
        with self.assertRaises(ValueError):
            check(MARKER.replace('1:1:0', '1:1:1'))
        with self.assertRaises(ValueError):
            instrument(events[1:], PROJECT)

    @unittest.skipUnless(HAS_DEPS, 'requires analysis dependencies')
    def test_bad_apk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'bad.apk'
            p.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(p)

    @unittest.skipUnless(HAS_DEPS and APK.is_file(), 'requires pinned APK and analysis dependencies')
    def test_native(self):
        report = inspect(APK)
        self.assertEqual(report['distance_arguments'], ['self.x', 'self.y', 'obj_player.x', 'obj_player.y'])
        self.assertEqual(report['finite_true_condition'], 'distance > 8000 + current epsilon')


if __name__ == '__main__':
    unittest.main()
