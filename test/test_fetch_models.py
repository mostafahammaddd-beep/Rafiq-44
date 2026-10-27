import pathlib
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import scripts.fetch_models as fetch_models  # noqa: E402


class ModelBundleValidationTests(unittest.TestCase):
    def test_checked_in_downloader_has_revision_fallback_not_stale_hard_fail(self):
        source = (ROOT / "scripts" / "fetch_models.py").read_text(encoding="utf-8")
        self.assertIn(
            "QURAN_LAB_REVISION was missing or malformed; resolving the immutable commit directly.",
            source,
        )
        self.assertNotIn(
            "QURAN_LAB_REVISION must be the 40-character commit SHA resolved by the workflow.",
            source,
        )

    def test_revision_fallback_resolves_when_environment_is_missing(self):
        with mock.patch("scripts.resolve_model_revision.resolve_revision", return_value="0123456789abcdef0123456789abcdef01234567") as resolve:
            self.assertEqual(
                fetch_models._resolve_revision("test-token"),
                "0123456789abcdef0123456789abcdef01234567",
            )
            resolve.assert_called_once_with("test-token")

    def test_accepts_exact_251_class_token_table(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "tokens.txt"
            path.write_text(
                "\n".join(
                    [f"unit{i} {i}" for i in range(250)] + ["<blk> 250"]
                ),
                encoding="utf-8",
            )
            metadata = fetch_models.token_metadata(path)
        self.assertIsNotNone(metadata)
        self.assertEqual(metadata["class_count"], 251)
        self.assertEqual(metadata["blank_id"], 250)
        self.assertEqual(metadata["blank_label"], "<blk>")

    def test_rejects_non_contiguous_vocabulary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "tokens.txt"
            path.write_text("a 0\nb 2\n", encoding="utf-8")
            self.assertIsNone(fetch_models.token_metadata(path))

    def test_rejects_wrong_class_count(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "tokens.txt"
            path.write_text("a 0\n<blk> 1\n", encoding="utf-8")
            self.assertIsNone(fetch_models.token_metadata(path))

    def test_manifest_cache_rejects_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            model = base / "model.onnx"
            tokens = base / "tokens.txt"
            lexicon = base / "lexicon.json"
            license_file = base / "LICENSE"
            manifest = base / "model_manifest.json"
            model.write_bytes(b"model bytes")
            tokens.write_text(
                "\n".join([f"unit{i} {i}" for i in range(250)] + ["<blk> 250"]),
                encoding="utf-8",
            )
            lexicon.write_text('{"1:1": ["a"]}', encoding="utf-8")
            license_file.write_text("NPL-1.2 license text\n" * 20, encoding="utf-8")
            patches = {
                "MODEL": model,
                "TOKENS": tokens,
                "LEXICON": lexicon,
                "LICENSE": license_file,
                "MANIFEST": manifest,
            }
            with mock.patch.multiple(fetch_models, **patches, REVISION="a" * 40):
                token_info = fetch_models.token_metadata(tokens)
                fetch_models.write_manifest(token_info)
                self.assertTrue(fetch_models.manifest_is_valid())
                model.write_bytes(b"tampered model bytes")
                self.assertFalse(fetch_models.manifest_is_valid())

    def test_accepts_json_mapping_or_list_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "ref.json"
            path.write_text('["a", "b"]', encoding="utf-8")
            self.assertTrue(fetch_models.valid_json(path))
            path.write_text('"not a reference map"', encoding="utf-8")
            self.assertFalse(fetch_models.valid_json(path))
            path.write_text('{broken json', encoding="utf-8")
            self.assertFalse(fetch_models.valid_json(path))


if __name__ == "__main__":
    unittest.main()
