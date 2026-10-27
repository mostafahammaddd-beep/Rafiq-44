/// Conservative diagnostic categories. These are educational labels, not a
/// religious ruling; the classifier emits uncertain whenever evidence is not
/// sufficient for the specific claim.
enum RecitationErrorClass { lahnJali, lahnKhafi, uncertain }

enum AcousticFindingKind {
  phonemeSubstitution,
  phonemeOmission,
  phonemeInsertion,
  wordOrder,
  vowelMismatch,
  maddDuration,
  ghunnaDuration,
  ikhfa,
  idgham,
  qalqala,
  tafkhim,
  tarqiq,
}

class DiagnosticEvidence {
  const DiagnosticEvidence({
    required this.kind,
    required this.rawFrameEvidenceAvailable,
    required this.frameAligned,
    required this.confidenceCalibrated,
    this.calibratedConfidence,
    this.expectedTokenId,
    this.observedTokenId,
    this.llrPerFrame,
    this.measuredDurationMs,
    this.allowedMinimumMs,
    this.allowedMaximumMs,
    this.tempoBaselineCalibrated = false,
    this.supportingEvidence = '',
  });

  final AcousticFindingKind kind;
  final bool rawFrameEvidenceAvailable;
  final bool frameAligned;
  final bool confidenceCalibrated;
  final double? calibratedConfidence;
  final int? expectedTokenId;
  final int? observedTokenId;
  final double? llrPerFrame;
  final double? measuredDurationMs;
  final double? allowedMinimumMs;
  final double? allowedMaximumMs;
  final bool tempoBaselineCalibrated;
  final String supportingEvidence;
}

class DiagnosticDecision {
  const DiagnosticDecision({
    required this.category,
    required this.reason,
    required this.isActionable,
  });

  final RecitationErrorClass category;
  final String reason;
  final bool isActionable;
}

class TajweedDiagnosticClassifier {
  const TajweedDiagnosticClassifier({
    this.minimumJaliConfidence = 0.97,
    this.minimumKhafiConfidence = 0.90,
  });

  final double minimumJaliConfidence;
  final double minimumKhafiConfidence;

  DiagnosticDecision classify(DiagnosticEvidence evidence) {
    if (!evidence.rawFrameEvidenceAvailable || !evidence.frameAligned) {
      return const DiagnosticDecision(
        category: RecitationErrorClass.uncertain,
        reason: 'لا تتوفر احتمالات إطارية ومحاذاة صوتية حقيقية لهذا الحكم.',
        isActionable: false,
      );
    }
    final double? confidence = evidence.calibratedConfidence;
    if (!evidence.confidenceCalibrated || confidence == null ||
        !confidence.isFinite || confidence < 0 || confidence > 1) {
      return const DiagnosticDecision(
        category: RecitationErrorClass.uncertain,
        reason: 'درجة الثقة غير معايرة على تسجيلات مستقلة موسومة.',
        isActionable: false,
      );
    }

    switch (evidence.kind) {
      case AcousticFindingKind.phonemeSubstitution:
      case AcousticFindingKind.phonemeOmission:
      case AcousticFindingKind.phonemeInsertion:
      case AcousticFindingKind.wordOrder:
      case AcousticFindingKind.vowelMismatch:
        if (confidence >= minimumJaliConfidence) {
          return const DiagnosticDecision(
            category: RecitationErrorClass.lahnJali,
            reason: 'اختلاف فونيمي/لفظي مدعوم بأدلة صوتية معايرة.',
            isActionable: true,
          );
        }
        return const DiagnosticDecision(
          category: RecitationErrorClass.uncertain,
          reason: 'دليل الخطأ اللفظي لا يتجاوز حد الثقة المحافظ.',
          isActionable: false,
        );
      case AcousticFindingKind.maddDuration:
      case AcousticFindingKind.ghunnaDuration:
      case AcousticFindingKind.ikhfa:
      case AcousticFindingKind.idgham:
      case AcousticFindingKind.qalqala:
      case AcousticFindingKind.tafkhim:
      case AcousticFindingKind.tarqiq:
        if (evidence.kind == AcousticFindingKind.maddDuration ||
            evidence.kind == AcousticFindingKind.ghunnaDuration) {
          final double? measured = evidence.measuredDurationMs;
          final double? minimum = evidence.allowedMinimumMs;
          final double? maximum = evidence.allowedMaximumMs;
          if (!evidence.tempoBaselineCalibrated || measured == null ||
              minimum == null || maximum == null || minimum > maximum ||
              !measured.isFinite || !minimum.isFinite || !maximum.isFinite) {
            return const DiagnosticDecision(
              category: RecitationErrorClass.uncertain,
              reason: 'قياس المدة يحتاج محاذاة ومعايرة سرعة القارئ ومدى هدف موثق.',
              isActionable: false,
            );
          }
          if (measured >= minimum && measured <= maximum) {
            return const DiagnosticDecision(
              category: RecitationErrorClass.uncertain,
              reason: 'المدة المقاسة ضمن المجال المقبول؛ لا يوجد دليل على خطأ في المدّة.',
              isActionable: false,
            );
          }
        }
        if (confidence >= minimumKhafiConfidence) {
          return const DiagnosticDecision(
            category: RecitationErrorClass.lahnKhafi,
            reason: 'دليل صوتي تجويدي قابل للقياس تجاوز حد الثقة المحدد.',
            isActionable: true,
          );
        }
        return const DiagnosticDecision(
          category: RecitationErrorClass.uncertain,
          reason: 'لا يكفي الدليل الصوتي للتمييز بين الأداء الصحيح والخطأ الخفي.',
          isActionable: false,
        );
    }
  }
}
