# Rafiq 0.4.3 CTC, model-pack and session-integrity implementation notes

## Added in this source update

- A CTC frame evidence model (`CtcFrameBatch`) with explicit shape, class count, frame step, global frame offset, blank id, and frame/class strides.
- CTC Viterbi forced alignment with CTC skip rules, explicit frame timestamps, and backtracking.
- A local one-phoneme forward-sum score comparing an expected token with competing token IDs. It is deliberately named/documented as a local CTC score, not a calibrated universal GOP score.
- A bounded revision-capable streaming Viterbi wrapper. It can revise token spans as new frame batches arrive, but requires raw frame log-probabilities that the current Sherpa Dart result does not provide.
- A robust tempo baseline that accepts only caller-verified short-vowel durations with high confidence, plus conservative movement estimates.
- A typed word-level wasl/waqf graph for supplied, verified alternatives. The live token matcher also accepts a rule-generated word-level waqf candidate only at a Sherpa endpoint; telemetry labels this candidate as approximate rather than a human-verified canonical reference.
- A conservative `TajweedDiagnosticClassifier`; it returns `uncertain` when raw frame evidence, timing, calibration, or tempo prerequisites are missing.
- Sherpa result tokens and timestamps are now carried across the isolate together with session ID, update sequence, model version, and inference latency.
- A debug-only telemetry surface shows the current expected phoneme string, decoded hypothesis, token/timestamp trace, latency, backend/version metadata, and explicit unavailability of raw CTC LLR and true frame duration.
- Session IDs reject stale updates from previous recordings; update sequence numbers reject duplicates/out-of-order events. Repeated fallback-evaluator failures are deduplicated, Unicode code points replace UTF-16 code units, a short exact match can recover a current word after a recent stutter/correction, and an endpoint may select an available word-level waqf variant.
- The old character-presence TajweedChecker no longer issues rule-level findings. Repeated characters or the presence of Arabic letters are not valid measurements of madd duration, ghunna quality, ikhfa, or tafkhim. In memorize mode, non-advancing failures now remain provisional: they show feedback but do not permanently change accuracy statistics or log a database mistake if the student self-corrects.
- The model fetch script resolves the current Hugging Face main reference to an immutable v3.1 source commit SHA at the start of CI, uses that SHA as the download revision/cache key, and writes `model_manifest.json` with source/version provenance and SHA-256 hashes for the model, tokens, lexicon, and license. It refuses fallback models, validates cache contents before reuse, and avoids mixing a model with another token file/lexicon. The loader verifies the four file fingerprints during import and keeps the installed model in app-private support storage.
- Recreated the missing `pubspec.yaml`, because the supplied archive did not contain one and the existing CI invokes `flutter pub get` at repository root.

## Important boundary: what is not yet a live model feature

The current `sherpa_onnx` Dart `OnlineRecognizerResult` exposes `text`, `tokens`, and `timestamps`, not the frame-level CTC `log_probs` needed for live CTC-GOP/LLR and full CTC forced alignment. See the current API reference: <https://pub.dev/documentation/sherpa_onnx/latest/sherpa_onnx/OnlineRecognizerResult-class.html>. The pinned model does expose frame log-probabilities in its ONNX graph, so a real native/ONNX bridge can provide them, but this source snapshot does not claim that bridge exists.

Accordingly, the new frame-level CTC components are implemented and unit tests are added, but they are **not wired into the production inference path**. The active app now matches actual decoded model token labels against tokenized canonical phonemes whenever possible, with an explicitly weaker Unicode fallback, endpoint-only approximate waqf alternatives, improved failure deduplication, and explicit UI disclosure. Sherpa token timestamps are shown as token timing diagnostics; their differences are not used as a definitive madd judgement. No code pretends to obtain raw probabilities from text.

To enable actual calibrated GOP and timing-based tajweed judgements, a subsequent change must add a compatible model inference path that returns the model's real frame-level log-probabilities (or a validated native bridge exposing them), then connect `CtcFrameBatch` -> `StreamingViterbiAligner` -> `CtcGopScorer` -> `TajweedDiagnosticClassifier`. This requires validating the actual ONNX input/output/state shapes and the feature frontend against the model export; it cannot be safely fabricated from the current archive.

## Verification status

- `python3 -m py_compile scripts/fetch_models.py scripts/resolve_model_revision.py scripts/patch_android.py test/test_fetch_models.py test/test_resolve_model_revision.py`: successful.
- `python3 -m unittest discover -s test -p 'test_*.py' -v`: 10 Python tests passed, covering token validation, JSON validation, tamper detection, and revision resolver behavior.
- GitHub Actions YAML parsing and relative Dart import paths: successful static checks.
- Dart/Flutter analysis and tests could not be run in this environment because the `dart` and `flutter` executables are not installed. The workflow runs them before building the APK.
- The original archive lacked `pubspec.yaml`, so the dependency set had to be reconstructed from the project's imports and `CLAUDE.md`. Run `flutter pub get`, `dart format lib test`, `flutter analyze`, and `flutter test` in a Flutter SDK environment before treating this snapshot as release-ready.


## Additional hardening in 0.4.3

- The microphone service now stops the native recorder before canceling its stream subscription, giving the recorder an opportunity to deliver its final buffered audio.
- `stopListening` keeps the active session subscribed while it submits a final partial audio buffer and waits for its response; it also places a drain barrier after all previously submitted full chunks before ending the session. This protects the final word from being discarded simply because the stream ended. These wait operations use a bounded timeout.
- Empty hypothesis updates no longer mark a missing-reference word as inconclusive before any audio-derived tokens exist. Once actual recognized content exists, a missing phoneme reference is explicitly `uncertain`, not correct.
- Uncertain memorization words are rendered distinctly from confirmed correct words and remain hidden where the memorization mode hides unrehearsed/incorrect words.
- Added regression tests for empty recognizer updates and distant exact substring matching.
- The model loader installs the separate model pack into app-private storage, validates all file hashes, and does not embed the ONNX file in Flutter assets.

## Release validation boundary

The editing environment does not contain the Flutter or Dart executable, so these Dart changes and Android build cannot be locally analyzed here. CI is configured to run those checks before artifact upload; treat the workflow result as the next source of compiler/test evidence. The raw-log-probability backend limitation remains as explained above.

- Expected phoneme tokenization now uses dynamic programming and refuses ambiguous segmentations rather than choosing a greedy split. `CtcFrameBatch` rejects NaN, positive infinity, and positive values that would indicate logits have been mislabeled as log-probabilities.
- A release-status report in Arabic separates implemented source features from features that remain unconnected to the live acoustic backend.


## Model distribution and stable update signing in 0.4.3

- `pubspec.yaml` no longer declares `assets/models/` as Flutter assets. CI attaches `rafiq-model-v3.1-pack` separately, when the model cache is first created or when `include_model_pack=true` is requested manually. The APK remains lightweight. The app's file picker imports the five pack files into app-private storage, validates their manifest and SHA-256 values, and preserves the model across ordinary upgrades when the same package ID and signing key are retained.
- CI supports stable signing via the secrets `RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD`. Without these secrets, a runner debug key is used as a development fallback; a fresh runner may use a different key, preventing in-place app updates.
- The raw CTC probability backend remains unconnected to live Sherpa inference as described above.


## Fix in 0.4.3: robust Hugging Face revision handoff

The revision resolver now writes the immutable commit SHA to both `GITHUB_OUTPUT` and `GITHUB_ENV`. The workflow validates the step output before using it as a cache key. `fetch_models.py` no longer fails immediately if `QURAN_LAB_REVISION` is absent or malformed: it resolves the SHA directly through the official Hugging Face API using `HF_TOKEN`, then records the resolved value for subsequent steps. This preserves immutable downloads and provides a clear diagnostic if API access is denied.
