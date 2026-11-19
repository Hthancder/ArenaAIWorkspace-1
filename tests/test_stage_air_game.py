import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.stage_air_game import DOCS, SWFS, stage


class StagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        for name in ("LostLife.swf", "application.xml", *SWFS, *DOCS):
            (self.source / name).write_bytes(name.encode())
        archive = self.root / "archive.zip"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("m1.swf", b"m1")
            z.writestr("ui.swf", b"ui")
        data = archive.read_bytes()
        halfway = len(data) // 2
        (self.source / "lib.zip.001").write_bytes(data[:halfway])
        (self.source / "lib.zip.002").write_bytes(data[halfway:])
        self.destination = self.root / "staged"

    def tearDown(self):
        self.temp.cleanup()

    def test_reconstructs_expected_structure(self):
        stage(self.source, self.destination)
        self.assertEqual((self.destination / "lib/m1.swf").read_bytes(), b"m1")
        self.assertEqual((self.destination / "lib/ui.swf").read_bytes(), b"ui")
        self.assertTrue((self.destination / "lib/doc/lang.xml").exists())
        self.assertTrue((self.destination / "application.xml").exists())

    def test_missing_part_leaves_no_output(self):
        (self.source / "lib.zip.001").unlink()
        with self.assertRaises(ValueError):
            stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_bad_archive_leaves_no_output(self):
        (self.source / "lib.zip.002").write_bytes(b"invalid")
        with self.assertRaises(zipfile.BadZipFile):
            stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_existing_destination_is_not_overwritten(self):
        self.destination.mkdir()
        with self.assertRaises(ValueError):
            stage(self.source, self.destination)


if __name__ == "__main__":
    unittest.main()
