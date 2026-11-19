import tempfile
import unittest
from pathlib import Path
from xml.dom import minidom

from tools.prepare_ios_descriptor import prepare


class DescriptorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.source = self.root / "application.xml"
        self.output = self.root / "ios.xml"
        self.source.write_text('''<?xml version="1.0"?>
<application xmlns="http://ns.adobe.com/air/application/32.0">
  <id>Test</id><initialWindow><content>Game.swf</content></initialWindow>
  <icon><image36x36>icons/36.png</image36x36></icon>
  <android><manifestAdditions><![CDATA[<manifest/>]]></manifestAdditions></android>
  <iPhone><InfoAdditions><![CDATA[<key>UIDeviceFamily</key><array><string>1</string></array>]]></InfoAdditions></iPhone>
</application>''')

    def tearDown(self):
        self.tmp.cleanup()

    def test_removes_missing_icons_and_android_but_keeps_ios_cdata(self):
        original = self.source.read_bytes()
        prepare(self.source, self.output)
        doc = minidom.parse(str(self.output))
        self.assertFalse(doc.getElementsByTagName("icon"))
        self.assertFalse(doc.getElementsByTagName("android"))
        self.assertTrue(doc.getElementsByTagName("iPhone"))
        self.assertIn(b"<![CDATA[<key>UIDeviceFamily</key>", self.output.read_bytes())
        self.assertEqual(self.source.read_bytes(), original)

    def test_refuses_to_overwrite(self):
        self.output.write_text("existing")
        with self.assertRaises(ValueError):
            prepare(self.source, self.output)
        self.assertEqual(self.output.read_text(), "existing")

    def test_missing_ios_settings_fails(self):
        self.source.write_text('<application xmlns="http://ns.adobe.com/air/application/32.0"/>')
        with self.assertRaises(ValueError):
            prepare(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_non_air_xml(self):
        self.source.write_text('<application/>')
        with self.assertRaises(ValueError):
            prepare(self.source, self.output)


if __name__ == "__main__":
    unittest.main()
