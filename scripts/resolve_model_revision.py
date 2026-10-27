#!/usr/bin/env python3
"""Resolve the gated Quran-Lab model's current main SHA without leaking secrets.

The workflow uses the returned immutable commit for both model download and
cache key. The token is sent only to Hugging Face's official API endpoint.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

API_URL = "https://huggingface.co/api/models/Quran-Lab/zipformer_p-arabic-v3"


def resolve_revision(token: str) -> str:
    if not token.strip():
        raise RuntimeError("HF_TOKEN is missing. Add a Hugging Face read token as a GitHub Actions secret.")
    request = urllib.request.Request(
        API_URL,
        headers={
            "Authorization": "Bearer " + token.strip(),
            "Accept": "application/json",
            "User-Agent": "rafiq-ci/0.4.3",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code in (401, 403, 404):
            raise RuntimeError(
                "Hugging Face denied access to Quran-Lab/zipformer_p-arabic-v3. "
                "Sign in, accept NPL-1.2/access terms, and ensure the HF_TOKEN has read access."
            ) from error
        raise RuntimeError(f"Hugging Face revision API failed with HTTP {error.code}.") from error
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        raise RuntimeError(f"Could not resolve the Hugging Face model revision: {error}") from error

    revision = payload.get("sha") if isinstance(payload, dict) else None
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise RuntimeError("Hugging Face API did not return a valid 40-character commit SHA.")
    return revision


def main() -> int:
    try:
        revision = resolve_revision(os.environ.get("HF_TOKEN", ""))
    except RuntimeError as error:
        print(f"::error::{error}")
        return 1
    print(f"Resolved Quran-Lab main to immutable commit {revision}.")
    # Expose the immutable SHA both as a step output (for cache keys) and as
    # a job environment variable (for subsequent scripts). This avoids a
    # blank step-output expression accidentally shadowing the resolved SHA.
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"revision={revision}\n")
    else:
        print(f"revision={revision}")

    env_path = os.environ.get("GITHUB_ENV")
    if env_path:
        with open(env_path, "a", encoding="utf-8") as output:
            output.write(f"QURAN_LAB_REVISION={revision}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
