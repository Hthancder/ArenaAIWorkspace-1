import struct
import tempfile
import unittest
from pathlib import Path

from tools.deadtown_poison_evidence import inspect, room_speeds


def make_room_container(record_size=20, version=15):
    gen = b'GEN8' + struct.pack('<I', 2) + bytes([0, version])
    room_start = 8 + len(gen) + 8
    room_record = room_start + 8
    strg_start = room_start + 8 + record_size + 8
    name_pointer = strg_start + 4
    record = struct.pack('<IIIII', name_pointer, 0, 1120, 630, 30)[:record_size]
    room_data = struct.pack('<II', 1, room_record) + record
    string_data = struct.pack('<I', 3) + b'abc\0'
    body = gen + b'ROOM' + struct.pack('<I', len(room_data)) + room_data
    body += b'STRG' + struct.pack('<I', len(string_data)) + string_data
    return b'FORM' + struct.pack('<I', len(body)) + body


class RoomSpeedTests(unittest.TestCase):
    def test_reads_default_speed(self):
        self.assertEqual(room_speeds(make_room_container()), [{'name': 'abc', 'default_speed': 30}])

    def test_rejects_truncated_room_and_wrong_version(self):
        with self.assertRaisesRegex(ValueError, 'truncated room'):
            room_speeds(make_room_container(record_size=19))
        with self.assertRaisesRegex(ValueError, 'version'):
            room_speeds(make_room_container(version=16))

ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / '.cache/deadtown-original.apk'
try:
    import capstone  # noqa: F401
    import elftools  # noqa: F401
    HAS_RE = True
except ImportError:
    HAS_RE = False


class PoisonEvidenceTests(unittest.TestCase):
    @unittest.skipUnless(HAS_RE, 'requires capstone and pyelftools')
    def test_wrong_apk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'wrong.apk'
            path.write_bytes(b'not the pinned APK')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                inspect(path)

    @unittest.skipUnless(APK.is_file() and HAS_RE, 'requires pinned APK and RE dependencies')
    def test_known_native_path(self):
        evidence = inspect(APK)
        self.assertEqual(evidence['field'], 9)
        self.assertEqual(evidence['field_value_multiplied_by'], [30, 60])
        self.assertEqual(evidence['variable_index'], 32)
        self.assertEqual(evidence['adjacent_variable_symbols'][-1], 'g_VAR_buff_poison_protect')
        self.assertEqual(evidence['player_object_name'], 'obj_player')
        self.assertEqual(evidence['buff_step_add_call'], '0x6022cc')
        step = evidence['player_step_evidence']
        self.assertEqual(step['variable_index'], 32)
        self.assertEqual(step['comparison_fallthrough_zeroes_variable_index'], 171)
        self.assertEqual(step['branch_target_zeroes_variable_index'], 32)
        self.assertEqual(step['candidate_upper_bound_index'], 911)
        self.assertEqual((step['comparison_epsilon_symbol'], step['initial_epsilon']), ('g_GMLMathEpsilon', 1e-10))
        self.assertIn('not an independently registered name', step['limitations'])
        poison = evidence['poison_timer_evidence']
        self.assertEqual((poison['index'], poison['candidate_bound_index'], poison['candidate_bound_initial_value']),
                         (171, 910, 1800))
        rooms = evidence['room_defaults']['rooms']
        self.assertEqual(len(rooms), 15)
        self.assertTrue(all(r['default_speed'] == 30 for r in rooms))
        self.assertTrue({'rom_play', 'rom_play_sewer', 'rom_play_defence'} <= {r['name'] for r in rooms})
        save = evidence['save_load_evidence']
        self.assertEqual(save['section'], 'player')
        self.assertEqual(save['keys_to_player_indices'], {'buffpoison': 171, 'buffpoisonprotect': 32})
        self.assertEqual([r['text'] for r in save['resolved_string_relocations']],
                         ['player', 'buffpoison', 'player', 'buffpoisonprotect'] * 2)
        modes = save['other_modes_protection']
        self.assertEqual({(item['mode'], item['action']) for item in modes},
                         {(mode, action) for mode in ('sewer', 'defence', 'defence_multi')
                          for action in ('save', 'load')})
        self.assertTrue(all(item['index'] == 32 and item['section']['text'] == 'player' and
                            item['key']['text'] == 'buffpoisonprotect' for item in modes))
        self.assertEqual(evidence['player_create_evidence']['candidate_bound_initial_value'], 18000)
        damage = evidence['poison_damage_evidence']
        self.assertEqual((damage['poison_index'], damage['health_candidate_index'], damage['damage_candidate_index']),
                         (171, 28, 914))
        self.assertEqual((damage['health_save_section']['text'], damage['health_save_key']['text']), ('player', 'hp'))
        self.assertEqual((damage['skill_id'], damage['skill_result_above_half_divisor']), (20, 2))
        self.assertEqual((damage['create_numerator_candidate_index'], damage['create_divisor']), (169, 4500))
        self.assertEqual((damage['numerator_save_section']['text'], damage['numerator_save_key']['text']),
                         ('player', 'hp_max'))
        self.assertEqual(damage['numerator_create_initial_value'], 100)
        self.assertIn('unverified', damage['limitations'])
        self.assertEqual(evidence['zombie5_step_evidence']['comparison_offset'], -900)
        self.assertEqual(evidence['zombie5_step_evidence']['fallthrough_set_value'], 900)
        self.assertEqual(evidence['g_vars_index_32']['symbol'], 'g_VAR_pointer')
        self.assertIn('not a verified', evidence['g_vars_index_32']['warning'])
        self.assertIn('unverified', evidence['interpretation'])


if __name__ == '__main__':
    unittest.main()
