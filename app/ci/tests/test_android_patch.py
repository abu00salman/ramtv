import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


class AndroidPatchTest(unittest.TestCase):
    def test_existing_internet_permission_still_gets_tv_features_and_is_idempotent(self):
        patch = pathlib.Path(__file__).resolve().parents[1] / "patch.py"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            manifest = root / "android/app/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            (root / "assets").mkdir()
            (root / "assets/banner.png").write_bytes(b"fixture")
            activity = root / "android/app/src/main/kotlin/com/ramzi/ramtv/MainActivity.kt"
            activity.parent.mkdir(parents=True)
            activity.write_text("package com.ramzi.ramtv\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity: FlutterActivity()")
            manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<uses-permission android:name="android.permission.INTERNET"/>
<application android:label="ramtv" android:usesCleartextTraffic="false">
<activity android:name=".MainActivity"><intent-filter>
<category android:name="android.intent.category.LAUNCHER"/>
</intent-filter></activity></application></manifest>''')
            subprocess.run([sys.executable, str(patch), "android"], cwd=root, check=True)
            first = manifest.read_text()
            first_activity = activity.read_text()
            subprocess.run([sys.executable, str(patch), "android"], cwd=root, check=True)
            self.assertEqual(first, manifest.read_text())
            self.assertEqual(first_activity, activity.read_text())
            self.assertIn("Configuration.UI_MODE_TYPE_TELEVISION", first_activity)
            tree = ET.fromstring(first)
            ns = "{http://schemas.android.com/apk/res/android}"
            features = {e.get(ns + "name"): e.get(ns + "required")
                        for e in tree.findall("uses-feature")}
            self.assertEqual(features["android.hardware.touchscreen"], "false")
            self.assertEqual(features["android.software.leanback"], "false")
            categories = [e.get(ns + "name") for e in tree.iter("category")]
            self.assertIn("android.intent.category.LEANBACK_LAUNCHER", categories)


if __name__ == "__main__":
    unittest.main()
