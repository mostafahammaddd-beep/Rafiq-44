import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AnalysisOptionsTests(unittest.TestCase):
    def test_stale_nested_project_copies_are_excluded_from_analysis(self):
        text = (ROOT / "analysis_options.yaml").read_text(encoding="utf-8")
        self.assertIn("exclude:", text)
        self.assertIn("rafiq_final_work/**", text)
        self.assertIn("rafiq_v*/**", text)


class FilePickerAndroidCompatibilityTests(unittest.TestCase):
    """file_picker >= 10.3.11 skips the Kotlin plugin on AGP 9 (built-in Kotlin).

    Flutter 3.47 generated projects keep android.builtInKotlin=false, so those
    versions never compile FilePickerPlugin.kt and the APK build fails with
    'cannot find symbol: class FilePickerPlugin'. 10.3.10 applies KGP itself.
    The Dart API must match the pinned major version (instance API in 10.x).
    """

    def test_pubspec_pins_file_picker_exactly_to_10_3_10(self):
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        match = re.search(r"^\s*file_picker:\s*(\S+)\s*$", pubspec, re.MULTILINE)
        self.assertIsNotNone(match, "file_picker dependency not found")
        self.assertEqual(
            match.group(1),
            "10.3.10",
            "file_picker must be pinned exactly; a caret range resolves to a "
            "release that does not compile on AGP 9 with builtInKotlin=false.",
        )

    def test_dart_code_uses_the_10x_instance_api(self):
        source = (ROOT / "lib" / "features" / "welcome" / "welcome_screen.dart").read_text(encoding="utf-8")
        self.assertIn("FilePicker.platform.pickFiles(", source)
        self.assertNotIn("await FilePicker.pickFiles(", source)


if __name__ == "__main__":
    unittest.main()
