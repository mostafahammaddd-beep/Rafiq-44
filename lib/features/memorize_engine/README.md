# Recitation session

The active on-device backend is Sherpa-ONNX streaming Zipformer2 CTC. The session controller now prefers matching the recognizer's **token labels** against the canonical reference tokenized by the exact `tokens.txt` vocabulary. If any reference symbols cannot be tokenized exactly, it falls back to normalized Unicode comparison and the developer overlay labels that fallback explicitly.

Sherpa's Dart result currently exposes decoded text, token labels and token timestamps, but not the raw frame-level CTC `log_probs`. The independent CTC forced aligner, substitution-aware local CTC score and streaming alignment classes are ready for genuine frame evidence, but the production recognizer path does not yet supply that evidence. For this reason the app must not treat token timestamp differences as phoneme duration or report a calibrated LLR/GOP/madd/ghunna judgment. The telemetry panel marks these metrics unavailable instead of inventing them.

The release workflow builds lightweight arm64 and arm32 APKs with the developer overlay enabled via `RAFIQ_ENABLE_TELEMETRY=true`. The large v3.1 model is a separate `rafiq-model-v3.1-pack` artifact that is imported once in the app and retained across ordinary APK upgrades. Choose only the ABI artifact appropriate for the target phone.
