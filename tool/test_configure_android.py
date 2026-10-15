import tempfile
import unittest
from pathlib import Path

from configure_android import configure_android


class ConfigureAndroidTests(unittest.TestCase):
    def make_project(self, root: Path, gradle_name: str, gradle_content: str) -> None:
        android = root / "android"
        activity = (
            android
            / "app"
            / "src"
            / "main"
            / "kotlin"
            / "com"
            / "example"
            / "app"
            / "MainActivity.kt"
        )
        activity.parent.mkdir(parents=True)
        activity.write_text(
            "package com.example.app\n\n"
            "import io.flutter.embedding.android.FlutterActivity\n\n"
            "class MainActivity : FlutterActivity()\n",
            encoding="utf-8",
        )

        manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
        manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '  <application android:label="test">\n'
            "  </application>\n"
            "</manifest>\n",
            encoding="utf-8",
        )
        (android / "gradle.properties").write_text("org.gradle.jvmargs=-Xmx2g\n")
        app_gradle = android / "app" / gradle_name
        app_gradle.write_text(gradle_content, encoding="utf-8")

    def test_configures_kotlin_project_idempotently(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.make_project(
                root,
                "build.gradle.kts",
                "android {\n"
                "    namespace = \"com.example.app\"\n"
                "    defaultConfig {\n"
                "        minSdk = flutter.minSdkVersion\n"
                "    }\n"
                "}\n",
            )

            configure_android(root)
            configure_android(root)

            activity = next((root / "android").rglob("MainActivity.kt")).read_text()
            manifest = (
                root / "android/app/src/main/AndroidManifest.xml"
            ).read_text()
            properties = (root / "android/gradle.properties").read_text()
            gradle = (root / "android/app/build.gradle.kts").read_text()

            self.assertIn("connectWhileGranted(resultCode == Activity.RESULT_OK)", activity)
            self.assertEqual(activity.count("connectWhileGranted"), 1)
            self.assertIn('android:extractNativeLibs="true"', manifest)
            self.assertEqual(manifest.count("android:extractNativeLibs"), 1)
            self.assertNotIn("android.bundle.enableUncompressedNativeLibs", properties)
            self.assertIn("minSdk = 24", gradle)
            self.assertIn("useLegacyPackaging = true", gradle)
            self.assertEqual(gradle.count("packaging {"), 1)

    def test_configures_groovy_project(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.make_project(
                root,
                "build.gradle",
                "android {\n"
                "    defaultConfig {\n"
                "        minSdkVersion flutter.minSdkVersion\n"
                "    }\n"
                "}\n",
            )

            configure_android(root)

            gradle = (root / "android/app/build.gradle").read_text()
            self.assertIn("minSdkVersion 24", gradle)
            self.assertIn("useLegacyPackaging true", gradle)
            self.assertIn("packagingOptions {", gradle)

    def test_removes_obsolete_android_bundle_setting(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.make_project(
                root,
                "build.gradle.kts",
                "android {\n    defaultConfig {\n        minSdk = 24\n    }\n}\n",
            )
            properties = root / "android/gradle.properties"
            properties.write_text(
                "android.bundle.enableUncompressedNativeLibs=false\n"
                "org.gradle.jvmargs=-Xmx2g\n",
                encoding="utf-8",
            )

            configure_android(root)

            self.assertNotIn(
                "android.bundle.enableUncompressedNativeLibs", properties.read_text()
            )
            self.assertIn("org.gradle.jvmargs=-Xmx2g", properties.read_text())


if __name__ == "__main__":
    unittest.main()
