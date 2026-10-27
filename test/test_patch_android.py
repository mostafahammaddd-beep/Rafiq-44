import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.patch_android import configure_release_signing  # noqa: E402


class StableReleaseSigningTests(unittest.TestCase):
    def test_kotlin_dsl_uses_configured_keystore_and_keeps_debug_fallback(self):
        gradle = '''plugins { id("com.android.application") }
android {
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'''
        patched = configure_release_signing(gradle, True)
        self.assertIn('create("rafiqRelease")', patched)
        self.assertIn('file("rafiq-release.keystore")', patched)
        self.assertIn('signingConfigs.getByName("rafiqRelease")', patched)
        self.assertIn('signingConfigs.getByName("debug")', patched)
        self.assertEqual(configure_release_signing(patched, True), patched)

    def test_groovy_dsl_uses_configured_keystore_and_keeps_debug_fallback(self):
        gradle = '''plugins { id 'com.android.application' }
android {
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
'''
        patched = configure_release_signing(gradle, False)
        self.assertIn('rafiqRelease {', patched)
        self.assertIn("file('rafiq-release.keystore')", patched)
        self.assertIn('signingConfigs.rafiqRelease : signingConfigs.debug', patched)
        self.assertEqual(configure_release_signing(patched, False), patched)


if __name__ == '__main__':
    unittest.main()
