import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.create_test_signing import generate


@unittest.skipUnless(shutil.which("openssl"), "OpenSSL required")
class TestSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.output = self.root / "signing"

    def tearDown(self):
        self.temp.cleanup()

    def test_creates_parseable_p12_and_signed_profile(self):
        password = "disposable-test-password"
        generate(self.output, password)
        subprocess.run(["openssl", "pkcs12", "-in", str(self.output / "test.p12"),
                        "-info", "-noout", "-passin", "env:AIR_TEST_P12_PASSWORD"],
                       env={**os.environ, "AIR_TEST_P12_PASSWORD": password},
                       check=True, capture_output=True)
        verified = subprocess.run(["openssl", "smime", "-verify", "-inform", "DER", "-noverify",
                                   "-in", str(self.output / "test.mobileprovision")],
                                  check=True, capture_output=True)
        profile = plistlib.loads(verified.stdout)
        self.assertEqual(profile["Entitlements"]["application-identifier"], "LOCALDEV01.*")
        self.assertEqual(profile["Platform"], ["iOS"])
        self.assertEqual(len(profile["DeveloperCertificates"]), 1)
        self.assertFalse((self.output / "key.pem").exists())

    def test_empty_password_does_not_create_directory(self):
        with self.assertRaises(ValueError):
            generate(self.output, "")
        self.assertFalse(self.output.exists())

    def test_existing_output_is_not_overwritten(self):
        self.output.mkdir()
        with self.assertRaises(ValueError):
            generate(self.output, "password")


if __name__ == "__main__":
    unittest.main()
