import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.materialize_deadtown_source import files_under, materialize, tree_digest, validate_inputs

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / '.cache/gmx/deadtown.gmx'
APK = ROOT / '.cache/deadtown-original.apk'
SOURCE = ROOT / 'deadtown-source'


class WorkspaceUnitTests(unittest.TestCase):
    def test_existing_destination_is_never_changed(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / 'existing'
            dest.mkdir()
            keep = dest / 'keep'
            keep.write_text('user data')
            with self.assertRaisesRegex(ValueError, 'destination exists'):
                validate_inputs('missing', 'missing', 'missing', dest)
            self.assertEqual(keep.read_text(), 'user data')

    def test_tree_digest_detects_content_and_paths_and_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'a').write_text('x')
            before = tree_digest(root)
            self.assertEqual(before[0], 1)
            (root / 'a').write_text('y')
            self.assertNotEqual(tree_digest(root), before)
            (root / 'link').symlink_to(root / 'a')
            with self.assertRaisesRegex(ValueError, 'symlink'):
                files_under(root)

    def test_wrong_upstream_is_rejected_before_output_creation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            upstream = root / 'wrong'
            upstream.mkdir()
            dest = root / 'output'
            with self.assertRaisesRegex(ValueError, 'pinned revision'):
                validate_inputs(upstream, root / 'no.apk', SOURCE, dest)
            self.assertFalse(dest.exists())


@unittest.skipUnless(UPSTREAM.is_dir() and APK.is_file() and shutil.which('nm'), 'requires pinned inputs and nm')
class WorkspaceIntegrationTests(unittest.TestCase):
    def test_real_inputs_and_authoritative_editable_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source'
            shutil.copytree(SOURCE, source)
            # User changes override upstream, and deletions do not resurrect old files.
            script = source / 'project/scripts/achievement_plus.gml'
            script.write_text(script.read_text() + '\n// workspace test edit\n')
            removed = source / 'project/scripts/leaderboard_post.gml'
            removed.unlink()
            asset = source / 'assets/sprites/images/spr_player_0.png'
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_bytes(b'user override sentinel')
            result = root / 'result'
            status = materialize(UPSTREAM, APK, source, result)
            self.assertEqual(status['state'], 'INCOMPLETE_NOT_FOR_RELEASE')
            report = json.loads((result / 'comparison.json').read_text())['comparison']['project_declared']
            self.assertEqual(status['native_scripts_missing_by_name'], len(report['native_scripts_missing_in_source']))
            self.assertEqual(status['native_objects_missing_by_name'], len(report['native_objects_missing_in_source']))
            self.assertEqual(status['native_events_missing_by_key'], len(report['native_event_keys_missing_in_source']))
            self.assertEqual(status['audio_descriptors_populated_without_transcoding'], 89)
            self.assertEqual(status['resource_reference_counts']['sound'], 90)
            self.assertEqual(status['resource_reference_counts']['background'], 30)
            self.assertEqual(status['native_backgrounds_missing_by_name'], 0)
            self.assertEqual(status['native_rooms_missing_by_name'], 8)
            self.assertEqual(status['native_sounds_missing_by_name'], 0)
            project = result / 'project'
            self.assertEqual((project / 'background/images/tile_sewer.png').read_bytes(),
                             (SOURCE / 'assets/background/images/tile_sewer.png').read_bytes())
            self.assertEqual((project / 'sound/audio/snd_eating.wav').read_bytes(),
                             (SOURCE / 'assets/sound/audio/snd_eating.wav').read_bytes())
            self.assertIn('// workspace test edit', (project / 'scripts/achievement_plus.gml').read_text())
            self.assertFalse((project / 'scripts/leaderboard_post.gml').exists())
            self.assertEqual((project / 'sprites/images/spr_player_0.png').read_bytes(), b'user override sentinel')
            self.assertTrue(any(x['path'].endswith('leaderboard_post.gml') for x in status['missing_referenced_files']))
            self.assertFalse(any(project.rglob('*.pfx')))
            self.assertFalse((project / 'datafiles/UnityAdsExt.gmez').exists())
            self.assertEqual(json.loads((result / 'status.json').read_text())['state'], status['state'])
            self.assertTrue((result / 'comparison.json').is_file())

    def test_status_reports_removed_room_background_and_sound(self):
        import xml.etree.ElementTree as ET
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source'
            shutil.copytree(SOURCE, source)
            path = source / 'project/deadtown.project.gmx'
            tree = ET.parse(path)
            for section, tag, name in (('backgrounds', 'background', 'tile_sewer'),
                                       ('rooms', 'room', 'rom_credits'),
                                       ('sounds', 'sound', 'snd_eating')):
                group = tree.getroot().find(section)
                for parent in group.iter():
                    found = next((item for item in parent if item.tag == tag and item.text and
                                  item.text.replace('\\', '/').split('/')[-1] == name), None)
                    if found is not None:
                        parent.remove(found)
                        break
                else:
                    self.fail(f'missing test resource {name}')
            tree.write(path, encoding='unicode')
            status = materialize(UPSTREAM, APK, source, root / 'result')
            self.assertEqual(status['native_backgrounds_missing_by_name'], 1)
            self.assertEqual(status['native_rooms_missing_by_name'], 9)
            self.assertEqual(status['native_sounds_missing_by_name'], 1)

    def test_bad_apk_and_credential_asset_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bad = root / 'bad.apk'
            bad.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'APK SHA-256'):
                validate_inputs(UPSTREAM, bad, SOURCE, root / 'output')
            source = root / 'source'
            shutil.copytree(SOURCE, source)
            asset = source / 'assets/secret.pfx'
            asset.parent.mkdir(exist_ok=True)
            asset.write_bytes(b'sentinel, not a real key')
            with self.assertRaisesRegex(ValueError, 'forbidden asset'):
                validate_inputs(UPSTREAM, APK, source, root / 'output')
            self.assertFalse((root / 'output').exists())


if __name__ == '__main__':
    unittest.main()
