#!/usr/bin/env python3
"""Fetch the pinned Quran-Lab v3.1 model family for a separate model pack.

This build intentionally refuses to publish another repository's model or an
unverified token table. Request access to Quran-Lab/zipformer_p-arabic-v3 on
Hugging Face, accept its NPL-1.2 terms, and provide a read token as HF_TOKEN.
The model is downloaded only on a GitHub Actions cache miss (or explicit re-upload) and is delivered as a separate artifact. The app imports it once into persistent private storage and runs inference offline.
"""

import hashlib
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

OUT_DIR = pathlib.Path("assets/models")
MODEL = OUT_DIR / "model.int8.onnx"
TOKENS = OUT_DIR / "tokens.txt"
LEXICON = OUT_DIR / "quran_phoneme_words.json"
LICENSE = OUT_DIR / "QURAN_LAB_NPL_1_2_LICENSE.txt"
MANIFEST = OUT_DIR / "model_manifest.json"

REPOSITORY = "Quran-Lab/zipformer_p-arabic-v3"
# The workflow resolves the authorized model repository's current main SHA
# before cache restore, then passes the same immutable SHA to this script.
REVISION = os.environ.get("QURAN_LAB_REVISION", "").strip()
BASE = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/" if REVISION else ""
FILES = (
    ("zipformer_p_arabic_v3.1.int8.onnx", MODEL),
    ("tokens.txt", TOKENS),
    ("ordered_quran_phonemes.json", LEXICON),
    ("LICENSE", LICENSE),
)
MIN_MODEL_BYTES = 50 * 1024 * 1024
MIN_TOKENS_BYTES = 100
EXPECTED_CLASSES = 251
EXPECTED_BLANK_ID = 250
ACTIVE_SOURCE = f"{REPOSITORY}@{REVISION}" if REVISION else REPOSITORY


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _is_hf_host(host):
    return bool(host) and (host == "huggingface.co" or host.endswith(".huggingface.co"))


def download(url, dest, token):
    """Download via atomic rename; only send the HF token to huggingface.co."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".part")
    try:
        tmp.unlink(missing_ok=True)
    except OSError:
        pass
    current = url
    for _ in range(8):
        host = urllib.parse.urlparse(current).hostname
        headers = {"User-Agent": "rafiq-ci/2.0"}
        if token and host == "huggingface.co" and _is_hf_host(host):
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(current, headers=headers)
        try:
            response = _OPENER.open(request, timeout=180)
        except urllib.error.HTTPError as err:
            if err.code in (301, 302, 303, 307, 308):
                location = err.headers.get("Location")
                if not location:
                    return err.code
                current = urllib.parse.urljoin(current, location)
                continue
            return err.code
        except (urllib.error.URLError, OSError, TimeoutError) as err:
            print(f"  network error: {err}")
            return -1
        try:
            with response, open(tmp, "wb") as out:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
            os.replace(tmp, dest)
            return 200
        except (OSError, TimeoutError) as err:
            print(f"  download interrupted: {err}")
            tmp.unlink(missing_ok=True)
            return -1
    return -1


def token_metadata(path):
    by_id = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw in handle:
                line = raw.rstrip("\r\n")
                if not line.strip():
                    continue
                parts = line.rsplit(None, 1)
                if len(parts) != 2:
                    return None
                try:
                    token_id = int(parts[1])
                except ValueError:
                    return None
                if token_id < 0 or token_id in by_id or not parts[0].strip():
                    return None
                by_id[token_id] = parts[0]
    except OSError:
        return None
    if len(by_id) != EXPECTED_CLASSES or set(by_id) != set(range(EXPECTED_CLASSES)):
        return None
    return {
        "class_count": EXPECTED_CLASSES,
        "blank_id": EXPECTED_BLANK_ID,
        "blank_label": by_id[EXPECTED_BLANK_ID],
    }


def valid_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            decoded = json.load(handle)
        return isinstance(decoded, (dict, list))
    except (OSError, ValueError):
        return False


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_is_valid():
    try:
        metadata = json.loads(MANIFEST.read_text(encoding="utf-8"))
        return (
            bool(re.fullmatch(r"[0-9a-f]{40}", REVISION))
            and metadata.get("repository") == REPOSITORY
            and metadata.get("revision") == REVISION
            and metadata.get("model_version") == "v3.1"
            and metadata.get("class_count_from_tokens") == EXPECTED_CLASSES
            and metadata.get("blank_id_from_token_labels") == EXPECTED_BLANK_ID
            and MODEL.is_file()
            and TOKENS.is_file()
            and LEXICON.is_file()
            and LICENSE.is_file()
            and LICENSE.stat().st_size > 100
            and token_metadata(TOKENS) is not None
            and valid_json(LEXICON)
            and metadata.get("model_sha256") == sha256_file(MODEL)
            and metadata.get("tokens_sha256") == sha256_file(TOKENS)
            and metadata.get("lexicon_sha256") == sha256_file(LEXICON)
            and metadata.get("license_sha256") == sha256_file(LICENSE)
        )
    except (OSError, ValueError, TypeError):
        return False


def write_manifest(token_info):
    metadata = {
        "schema_version": 2,
        "repository": REPOSITORY,
        "revision": REVISION,
        "source": ACTIVE_SOURCE,
        "model_version": "v3.1",
        "model_filename": MODEL.name,
        "model_sha256": sha256_file(MODEL),
        "tokens_sha256": sha256_file(TOKENS),
        "lexicon_sha256": sha256_file(LEXICON),
        "license_filename": LICENSE.name,
        "license_sha256": sha256_file(LICENSE),
        "class_count_from_tokens": token_info["class_count"],
        "blank_id_from_token_labels": token_info["blank_id"],
        "raw_frame_log_probs_exposed_by_flutter_backend": False,
    }
    tmp = MANIFEST.with_name(MANIFEST.name + ".part")
    tmp.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, MANIFEST)


def _resolve_revision(token):
    """Resolve the immutable model commit if the workflow env is missing/bad.

    The workflow normally writes QURAN_LAB_REVISION through GITHUB_ENV and
    exposes the same value as a step output. The fallback makes this script
    robust when run manually or when a GitHub expression is unexpectedly empty.
    """
    try:
        if __package__:
            from .resolve_model_revision import resolve_revision
        else:
            from resolve_model_revision import resolve_revision
        return resolve_revision(token)
    except (RuntimeError, ImportError) as error:
        print(f"::error::Could not resolve the authorized model revision: {error}")
        return None


def main():
    global REVISION, BASE, ACTIVE_SOURCE
    token = os.environ.get("HF_TOKEN", "").strip()
    env_revision = os.environ.get("QURAN_LAB_REVISION", REVISION).strip()
    if re.fullmatch(r"[0-9a-f]{40}", env_revision):
        REVISION = env_revision
    else:
        print("::warning::QURAN_LAB_REVISION was missing or malformed; resolving the immutable commit directly.")
        resolved = _resolve_revision(token)
        if not resolved or not re.fullmatch(r"[0-9a-f]{40}", resolved):
            print("::error::A valid 40-character model commit SHA is required; revision resolution failed.")
            return 2
        REVISION = resolved
        # Keep subsequent steps and reruns consistent with the resolved value.
        output_path = os.environ.get("GITHUB_OUTPUT")
        if output_path:
            with open(output_path, "a", encoding="utf-8") as handle:
                handle.write(f"revision={REVISION}\n")
        env_path = os.environ.get("GITHUB_ENV")
        if env_path:
            with open(env_path, "a", encoding="utf-8") as handle:
                handle.write(f"QURAN_LAB_REVISION={REVISION}\n")
    BASE = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/"
    ACTIVE_SOURCE = f"{REPOSITORY}@{REVISION}"
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if manifest_is_valid():
        print(f"Verified cached model pack: {REPOSITORY}@{REVISION}")
        print(f"  model:   {MODEL.stat().st_size / 1048576:.1f} MiB")
        print(f"  lexicon: {LEXICON.stat().st_size / 1048576:.1f} MiB")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
                handle.write("models_ready=true\n")
        return 0

    # An incomplete or unverifiable cache must never be paired with another
    # model's tokens or canonical lexicon.
    for path in (MODEL, TOKENS, LEXICON, LICENSE, MANIFEST):
        path.unlink(missing_ok=True)

    if not token:
        print("::error::HF_TOKEN is missing. Grant model access and add the token as a GitHub Actions secret.")
        return 2

    print(f"Downloading the pinned v3.1 family from {REPOSITORY}@{REVISION}")
    for remote_name, destination in FILES:
        status = download(BASE + remote_name, destination, token)
        if status != 200:
            destination.unlink(missing_ok=True)
            print(f"::error::Could not download {remote_name}; HTTP/network status={status}.")
            print("Check that the Hugging Face account accepted the NPL-1.2 terms and was granted access.")
            for path in (MODEL, TOKENS, LEXICON, LICENSE, MANIFEST):
                path.unlink(missing_ok=True)
            return 3
        print(f"  {destination.name}: {destination.stat().st_size / 1048576:.1f} MiB")

    if MODEL.stat().st_size < MIN_MODEL_BYTES:
        print("::error::Downloaded ONNX model is implausibly small; refusing to publish it as a model pack.")
        return 4
    if TOKENS.stat().st_size < MIN_TOKENS_BYTES:
        print("::error::tokens.txt is implausibly small.")
        return 4
    token_info = token_metadata(TOKENS)
    if token_info is None:
        print("::error::tokens.txt does not contain the expected contiguous 251-class vocabulary.")
        return 4
    if not valid_json(LEXICON):
        print("::error::The canonical phoneme lexicon is not valid JSON.")
        return 4
    if not LICENSE.is_file() or LICENSE.stat().st_size < 100:
        print("::error::The model license text is missing; refusing redistribution without it.")
        return 4

    write_manifest(token_info)
    print("Verified the model, token table, canonical lexicon, and license; wrote model_manifest.json")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write("models_ready=true\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
