import pathlib
import contextlib
import io
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import scripts.resolve_model_revision as resolver  # noqa: E402


class ResolveModelRevisionTests(unittest.TestCase):
    def test_main_exports_revision_to_output_and_environment(self):
        import os
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            output_path = pathlib.Path(directory) / "github_output"
            env_path = pathlib.Path(directory) / "github_env"
            with mock.patch.dict(os.environ, {
                "HF_TOKEN": "test-token",
                "GITHUB_OUTPUT": str(output_path),
                "GITHUB_ENV": str(env_path),
            }, clear=False), mock.patch.object(
                resolver, "resolve_revision", return_value="0123456789abcdef0123456789abcdef01234567"
            ), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(resolver.main(), 0)
            self.assertIn("revision=0123456789abcdef0123456789abcdef01234567", output_path.read_text())
            self.assertIn("QURAN_LAB_REVISION=0123456789abcdef0123456789abcdef01234567", env_path.read_text())

    def test_requires_token(self):
        with self.assertRaisesRegex(RuntimeError, "HF_TOKEN is missing"):
            resolver.resolve_revision("")

    def test_resolves_valid_commit_sha(self):
        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return b'{"sha":"0123456789abcdef0123456789abcdef01234567"}'

        with mock.patch.object(resolver.urllib.request, "urlopen", return_value=FakeResponse()):
            self.assertEqual(
                resolver.resolve_revision("test-token"),
                "0123456789abcdef0123456789abcdef01234567",
            )

    def test_rejects_malformed_sha(self):
        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return b'{"sha":"main"}'

        with mock.patch.object(resolver.urllib.request, "urlopen", return_value=FakeResponse()):
            with self.assertRaisesRegex(RuntimeError, "valid 40-character commit SHA"):
                resolver.resolve_revision("test-token")


if __name__ == "__main__":
    unittest.main()
