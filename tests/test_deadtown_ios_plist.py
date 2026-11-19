import unittest

from tools.prepare_deadtown_ios_plist import BUNDLE_ID, LANDSCAPE, prepare


class LandscapePlistTests(unittest.TestCase):
    def test_forces_landscape_and_preserves_other_values(self):
        original = {'MinimumOSVersion': '15.0', 'CFBundleExecutable': 'gmRunner',
                    'CFBundleVersion': '10203', 'UIFileSharingEnabled': True,
                    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait']}
        result = prepare(original)
        self.assertEqual(result['UISupportedInterfaceOrientations'], LANDSCAPE)
        self.assertEqual(result['UISupportedInterfaceOrientations~ipad'], LANDSCAPE)
        self.assertTrue(result['UIRequiresFullScreen'])
        self.assertTrue(result['UIFileSharingEnabled'])
        self.assertEqual(result['CFBundleVersion'], '10204')
        self.assertEqual(result['CFBundleIdentifier'], BUNDLE_ID)
        self.assertEqual(original['UISupportedInterfaceOrientations'], ['UIInterfaceOrientationPortrait'])

    def test_rejects_wrong_runner_or_version(self):
        for info in ({}, {'MinimumOSVersion': '17.0', 'CFBundleExecutable': 'app'},
                     {'MinimumOSVersion': '15.0', 'CFBundleExecutable': 'app', 'CFBundleVersion': '1.0'}):
            with self.subTest(info=info), self.assertRaises(ValueError):
                prepare(info)


if __name__ == '__main__':
    unittest.main()
