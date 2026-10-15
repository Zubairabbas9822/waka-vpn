#!/usr/bin/env python3
"""Apply the openvpn_flutter Android integration to Flutter-generated files."""

from __future__ import annotations

import re
from pathlib import Path


def _configure_main_activity(android_dir: Path) -> None:
    candidates = list((android_dir / "app" / "src" / "main").rglob("MainActivity.kt"))
    if len(candidates) != 1:
        raise RuntimeError(
            f"Expected one generated MainActivity.kt, found {len(candidates)}."
        )

    activity = candidates[0]
    content = activity.read_text(encoding="utf-8")
    match = re.search(r"(?m)^\s*package\s+([A-Za-z0-9_.]+)\s*$", content)
    if match is None:
        raise RuntimeError(f"Could not read Kotlin package name from {activity}.")

    package_name = match.group(1)
    activity.write_text(
        f"""package {package_name}

import android.app.Activity
import android.content.Intent
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {{
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {{
        if (requestCode == 24) {{
            OpenVPNFlutterPlugin.connectWhileGranted(resultCode == Activity.RESULT_OK)
        }}
        super.onActivityResult(requestCode, resultCode, data)
    }}
}}
""",
        encoding="utf-8",
    )


def _configure_manifest(android_dir: Path) -> None:
    manifest = android_dir / "app" / "src" / "main" / "AndroidManifest.xml"
    content = manifest.read_text(encoding="utf-8")
    match = re.search(r"<application\b[^>]*>", content, flags=re.DOTALL)
    if match is None:
        raise RuntimeError(f"No <application> element found in {manifest}.")

    application_tag = match.group(0)
    attribute = re.compile(r'\bandroid:extractNativeLibs\s*=\s*["\'][^"\']*["\']')
    if attribute.search(application_tag):
        application_tag = attribute.sub(
            'android:extractNativeLibs="true"', application_tag
        )
    else:
        application_tag = application_tag[:-1] + ' android:extractNativeLibs="true">'
    content = content[: match.start()] + application_tag + content[match.end() :]
    manifest.write_text(content, encoding="utf-8")


def _configure_gradle_properties(android_dir: Path) -> None:
    properties = android_dir / "gradle.properties"
    content = properties.read_text(encoding="utf-8") if properties.exists() else ""
    setting = "android.bundle.enableUncompressedNativeLibs=false"
    if re.search(r"(?m)^\s*android\.bundle\.enableUncompressedNativeLibs\s*=", content):
        content = re.sub(
            r"(?m)^\s*android\.bundle\.enableUncompressedNativeLibs\s*=.*$",
            setting,
            content,
        )
    else:
        content = content.rstrip() + "\n" + setting + "\n"
    properties.write_text(content, encoding="utf-8")


def _configure_app_gradle(android_dir: Path) -> None:
    app_dir = android_dir / "app"
    gradle_files = [
        path
        for path in (app_dir / "build.gradle.kts", app_dir / "build.gradle")
        if path.exists()
    ]
    if len(gradle_files) != 1:
        raise RuntimeError(
            f"Expected one app Gradle file, found {[str(path) for path in gradle_files]}."
        )

    gradle_file = gradle_files[0]
    content = gradle_file.read_text(encoding="utf-8")
    is_kotlin = gradle_file.suffix == ".kts"

    if is_kotlin:
        content = re.sub(
            r"(?m)^(\s*)minSdk\s*=\s*flutter\.minSdkVersion\s*$",
            r"\g<1>minSdk = 24",
            content,
        )
        packaging_block = (
            "    packaging {\n"
            "        jniLibs {\n"
            "            useLegacyPackaging = true\n"
            "        }\n"
            "    }\n"
        )
        existing = re.search(r"(?m)^\s*useLegacyPackaging\s*=\s*\w+", content)
        if existing:
            content = content[: existing.start()] + re.sub(
                r"useLegacyPackaging\s*=\s*\w+",
                "useLegacyPackaging = true",
                existing.group(0),
            ) + content[existing.end() :]
        else:
            marker = re.search(r"(?m)^(\s*)defaultConfig\s*\{", content)
            if marker is None:
                raise RuntimeError(f"No defaultConfig block found in {gradle_file}.")
            indent = marker.group(1)
            block = packaging_block.replace("    ", indent, 1)
            content = content[: marker.start()] + block + content[marker.start() :]
    else:
        content = re.sub(
            r"(?m)^(\s*)minSdkVersion\s+flutter\.minSdkVersion\s*$",
            r"\g<1>minSdkVersion 24",
            content,
        )
        packaging_block = (
            "    packagingOptions {\n"
            "        jniLibs {\n"
            "            useLegacyPackaging true\n"
            "        }\n"
            "    }\n"
        )
        existing = re.search(r"(?m)^\s*useLegacyPackaging\s*(?:=\s*)?\w+", content)
        if existing:
            content = content[: existing.start()] + re.sub(
                r"useLegacyPackaging\s*(?:=\s*)?\w+",
                "useLegacyPackaging true",
                existing.group(0),
            ) + content[existing.end() :]
        else:
            marker = re.search(r"(?m)^(\s*)defaultConfig\s*\{", content)
            if marker is None:
                raise RuntimeError(f"No defaultConfig block found in {gradle_file}.")
            indent = marker.group(1)
            block = packaging_block.replace("    ", indent, 1)
            content = content[: marker.start()] + block + content[marker.start() :]

    gradle_file.write_text(content, encoding="utf-8")


def configure_android(project_root: Path) -> None:
    android_dir = project_root / "android"
    if not android_dir.is_dir():
        raise RuntimeError(f"Android project not found at {android_dir}; run flutter create first.")

    _configure_main_activity(android_dir)
    _configure_manifest(android_dir)
    _configure_gradle_properties(android_dir)
    _configure_app_gradle(android_dir)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    configure_android(root)
    print("Configured Android VPN consent callback and OpenVPN native libraries.")


if __name__ == "__main__":
    main()
