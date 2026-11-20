import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

from tools.deadtown_native_lang import GMX_CALL
from tools.prepare_deadtown_lang_table_probe import prepare, rewrite, safe_literal
from tools.prepare_deadtown_offline import PatchError

ROOT = Path(__file__).resolve().parents[1]
APK = Path(os.environ.get('DEADTOWN_TEST_APK', ROOT / '.cache/deadtown-original.apk'))
OFFLINE = Path(os.environ.get('DEADTOWN_TEST_OFFLINE', ROOT / '.cache/deadtown-offline'))
EVENTS = Path(os.environ.get('DEADTOWN_TEST_EVENTS', ROOT / '.cache/events.json'))
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


def row(*values):
    return {'arguments': [{'type': 'string', 'value': v} for v in values]}


class LanguageTableUnitTests(unittest.TestCase):
    def test_replace_exact_calls_without_losing_other_code(self):
        body = 'lang_init()\nlang_add("Old","옛날","","")\n// keep\nother()\n'
        output = rewrite(body, [('Old', '옛날', '', '')], [row('New', '새로', '', ''), row('New', '나중', '', '')])
        self.assertEqual(GMX_CALL.findall(output), [('New', '새로', '', ''), ('New', '나중', '', '')])
        self.assertIn('// keep\nother()', output)
        with self.assertRaisesRegex(PatchError, 'unexpected old language'):
            rewrite(body, [('Different', '', '', '')], [row('X', '', '', '')])
        with self.assertRaisesRegex(PatchError, 'exactly one'):
            rewrite(body + 'lang_init()\n', [('Old', '옛날', '', '')], [row('X', '', '', '')])

    def test_rejects_gml_injection(self):
        for value in ('bad"stuff', 'bad\\stuff', 'bad\nstuff', None):
            with self.assertRaisesRegex(PatchError, 'unsupported'):
                safe_literal(value)
        with self.assertRaisesRegex(PatchError, 'argument layout'):
            rewrite('lang_init()\n', [], [{'arguments': []}])

    def test_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'result'
            dest.write_text('keep')
            with self.assertRaisesRegex(PatchError, 'already exists'):
                prepare('none', 'none', 'none', dest)
            self.assertEqual(dest.read_text(), 'keep')


@unittest.skipUnless(HAS_RE and APK.is_file() and EVENTS.is_file() and OFFLINE.is_dir(),
                     'requires pinned APK, offline source, event JSON and RE dependencies')
class LanguageTableIntegrationTests(unittest.TestCase):
    def test_candidate_only_and_unmodified_inputs(self):
        before = hashlib.sha256(EVENTS.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'events.json'
            self.assertEqual(prepare(EVENTS, OFFLINE, APK, dest), (362, 465))
            data = json.loads(dest.read_text(encoding='utf-8'))
            event = next(e for e in data if e['object'] == 'sys_global' and e['attributes'].get('eventtype') == '0')
            calls = GMX_CALL.findall(event['gml'])
            self.assertEqual(len(calls), 465)
            self.assertEqual(next(c for c in calls if c[0] == 'Gas mask'), ('Gas mask', '방독면', '', ''))
            duplicates = [c[1] for c in calls if c[0] == 'Light machine gun']
            self.assertEqual(duplicates, ['라이트 머신건', '라이트 머신 건'])
        self.assertEqual(hashlib.sha256(EVENTS.read_bytes()).hexdigest(), before)


if __name__ == '__main__':
    unittest.main()
