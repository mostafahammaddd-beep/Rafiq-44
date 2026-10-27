import 'dart:typed_data';

import 'ctc_forced_aligner.dart';
import 'ctc_types.dart';

class StreamingAlignmentSnapshot {
  const StreamingAlignmentSnapshot({
    required this.revision,
    required this.alignment,
    required this.changedTargetIndices,
    required this.isFinal,
    this.unavailableReason,
  });

  final int revision;
  final CtcAlignment? alignment;
  final List<int> changedTargetIndices;
  final bool isFinal;
  final String? unavailableReason;

  bool get hasAlignment => alignment != null;
}

/// Bounded, revision-capable streaming Viterbi wrapper.
///
/// This re-runs exact CTC Viterbi on the current segment whenever a new batch
/// arrives. Thus provisional token boundaries can move backwards as more
/// acoustic frames arrive, rather than freezing the first greedy alignment.
/// It is intentionally bounded: call [resetSegment] at a verified endpoint
/// before exceeding [maxBufferedFrames]. The class requires genuine frame
/// log-probabilities and is not connected to the current text-only Sherpa API.
class StreamingViterbiAligner {
  StreamingViterbiAligner({
    required List<int> targetTokenIds,
    this.maxBufferedFrames = 2400,
    CtcForcedAligner aligner = const CtcForcedAligner(),
  })  : targetTokenIds = List<int>.unmodifiable(targetTokenIds),
        _aligner = aligner {
    if (this.targetTokenIds.isEmpty) {
      throw ArgumentError('At least one target token is required.');
    }
    if (maxBufferedFrames < 16) {
      throw ArgumentError.value(maxBufferedFrames, 'maxBufferedFrames');
    }
  }

  final List<int> targetTokenIds;
  final int maxBufferedFrames;
  final CtcForcedAligner _aligner;
  final List<Float32List> _frames = <Float32List>[];
  int? _classCount;
  int? _blankId;
  double? _frameStepMs;
  int? _globalStartFrame;
  CtcAlignment? _lastAlignment;
  int _revision = 0;

  int get bufferedFrames => _frames.length;
  int get revision => _revision;

  StreamingAlignmentSnapshot append(CtcFrameBatch batch) {
    _validateBatch(batch);
    if (_frames.length + batch.frameCount > maxBufferedFrames) {
      throw StateError(
        'Streaming CTC segment exceeded $maxBufferedFrames frames; '
        'finish or reset the segment before appending more audio.',
      );
    }
    _classCount ??= batch.classCount;
    _blankId ??= batch.blankId;
    _frameStepMs ??= batch.frameStepMs;
    _globalStartFrame ??= batch.globalStartFrame;

    for (int frame = 0; frame < batch.frameCount; frame++) {
      final Float32List row = Float32List(batch.classCount);
      for (int token = 0; token < batch.classCount; token++) {
        row[token] = batch.logProb(frame, token);
      }
      _frames.add(row);
    }

    CtcAlignment next;
    try {
      final Float32List flat = Float32List(_frames.length * _classCount!);
      int offset = 0;
      for (final Float32List row in _frames) {
        flat.setRange(offset, offset + row.length, row);
        offset += row.length;
      }
      next = _aligner.align(
        batch: CtcFrameBatch(
          logProbs: flat,
          frameCount: _frames.length,
          classCount: _classCount!,
          frameStepMs: _frameStepMs!,
          blankId: _blankId!,
          globalStartFrame: _globalStartFrame!,
          source: batch.source,
        ),
        targetTokenIds: targetTokenIds,
      );
    } on StateError catch (error) {
      return StreamingAlignmentSnapshot(
        revision: _revision,
        alignment: null,
        changedTargetIndices: const <int>[],
        isFinal: false,
        unavailableReason: error.message,
      );
    }

    final List<int> changed = <int>[];
    final CtcAlignment? previous = _lastAlignment;
    if (previous == null) {
      changed.addAll(List<int>.generate(next.spans.length, (int index) => index));
    } else {
      for (int i = 0; i < next.spans.length; i++) {
        final AlignmentSpan before = previous.spans[i];
        final AlignmentSpan after = next.spans[i];
        if (before.startFrame != after.startFrame ||
            before.endFrameExclusive != after.endFrameExclusive) {
          changed.add(i);
        }
      }
    }
    _lastAlignment = next;
    _revision++;
    return StreamingAlignmentSnapshot(
      revision: _revision,
      alignment: next,
      changedTargetIndices: List<int>.unmodifiable(changed),
      isFinal: false,
    );
  }

  StreamingAlignmentSnapshot finish() {
    return StreamingAlignmentSnapshot(
      revision: _revision,
      alignment: _lastAlignment,
      changedTargetIndices: const <int>[],
      isFinal: true,
      unavailableReason: _lastAlignment == null
          ? 'لا تتوفر محاذاة صالحة لهذا المقطع الصوتي.'
          : null,
    );
  }

  void resetSegment() {
    _frames.clear();
    _classCount = null;
    _blankId = null;
    _frameStepMs = null;
    _globalStartFrame = null;
    _lastAlignment = null;
    _revision = 0;
  }

  void _validateBatch(CtcFrameBatch batch) {
    if (_frames.isNotEmpty) {
      if (batch.classCount != _classCount || batch.blankId != _blankId ||
          batch.frameStepMs != _frameStepMs) {
        throw ArgumentError('CTC metadata changed within one streaming segment.');
      }
      final int expectedOffset = _globalStartFrame! + _frames.length;
      if (batch.globalStartFrame != expectedOffset) {
        throw ArgumentError(
          'Non-contiguous frame batches: expected global frame $expectedOffset, '
          'received ${batch.globalStartFrame}.',
        );
      }
    }
  }
}
