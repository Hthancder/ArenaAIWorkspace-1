import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from tools.build_test_ipa import build


class ExperimentalBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.stage = self.root / "game"
        for name in ("LostLife.swf", "lib/ui.swf", "lib/m1.swf", "lib/doc/lang.xml"):
            p = self.stage / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b"placeholder")
        (self.stage / "application.xml").write_text(
            '<application xmlns="http://ns.adobe.com/air/application/32.0"><iPhone/></application>')
        self.output = self.root / "result.ipa"

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def fake_credentials(path, password):
        path.mkdir()
        (path / "test.p12").write_bytes(b"placeholder")
        (path / "test.mobileprovision").write_bytes(b"placeholder")

    @staticmethod
    def fake_adt(command, check):
        ipa = Path(command[command.index("-provisioning-profile") + 2])
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/Test.app/Test", b"placeholder")
        return subprocess.CompletedProcess(command, 0)

    def test_passes_expected_target_and_cleans_signing_files(self):
        with patch("tools.build_test_ipa.generate", side_effect=self.fake_credentials), \
             patch("tools.build_test_ipa.subprocess.run", side_effect=self.fake_adt) as run:
            build(self.stage, self.output, "fake-adt")
        command = run.call_args.args[0]
        self.assertIn("ipa-test-interpreter", command)
        self.assertIn("lib", command)
        self.assertTrue(self.output.exists())
        self.assertFalse(Path(command[command.index("-keystore") + 1]).exists())

    def test_packaging_failure_does_not_leave_output(self):
        with patch("tools.build_test_ipa.generate", side_effect=self.fake_credentials), \
             patch("tools.build_test_ipa.subprocess.run", side_effect=subprocess.CalledProcessError(1, "adt")):
            with self.assertRaises(subprocess.CalledProcessError):
                build(self.stage, self.output, "fake-adt")
        self.assertFalse(self.output.exists())

    def test_missing_staged_assets_fail_before_build(self):
        (self.stage / "lib/ui.swf").unlink()
        with self.assertRaises(ValueError):
            build(self.stage, self.output, "fake-adt")
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
