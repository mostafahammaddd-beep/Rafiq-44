import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelPaths {
  const ModelPaths({
    required this.modelPath,
    required this.tokensPath,
    this.lexiconPath,
    this.modelVersion = 'unknown',
    this.modelSha256,
    this.tokensSha256,
    this.classCount,
    this.blankId,
  });

  final String modelPath;
  final String tokensPath;
  final String? lexiconPath;
  final String modelVersion;
  final String? modelSha256;
  final String? tokensSha256;
  final int? classCount;
  final int? blankId;
}

/// Keeps the large acoustic model in app-private persistent storage instead of
/// embedding it in every APK. The user imports a verified model pack once;
/// ordinary app upgrades preserve the files under Application Support.
class ModelLoaderService {
  static const String modelFilename = 'model.int8.onnx';
  static const String tokensFilename = 'tokens.txt';
  static const String lexiconFilename = 'quran_phoneme_words.json';
  static const String manifestFilename = 'model_manifest.json';
  static const String licenseFilename = 'QURAN_LAB_NPL_1_2_LICENSE.txt';
  static const String versionTag = 'v3_1_external_pack_v1';

  static const String _repository = 'Quran-Lab/zipformer_p-arabic-v3';
  static const int _expectedClasses = 251;
  static const int _expectedBlankId = 250;
  static const int _minimumModelBytes = 50 * 1024 * 1024;

  Future<Directory> _modelsDirectory() async {
    final Directory support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'models'));
  }

  Future<bool> isInstalled() async => await findInstalled() != null;

  /// Finds a previously imported, verified model without hashing the 100+ MB
  /// ONNX file at every app start. The marker is only written after import-time
  /// verification of all files, including the license.
  Future<ModelPaths?> findInstalled() async {
    final Directory dir = await _modelsDirectory();
    final String modelPath = p.join(dir.path, modelFilename);
    final String tokensPath = p.join(dir.path, tokensFilename);
    final String lexiconPath = p.join(dir.path, lexiconFilename);
    final String manifestPath = p.join(dir.path, manifestFilename);
    final File manifestFile = File(manifestPath);
    final Map<String, dynamic>? manifest = await _readManifest(manifestFile);
    if (manifest == null || !_validManifestMetadata(manifest)) {
      return null;
    }

    final File modelFile = File(modelPath);
    final File tokensFile = File(tokensPath);
    final File lexiconFile = File(lexiconPath);
    final File licenseFile = File(p.join(dir.path, licenseFilename));
    if (!await modelFile.exists() ||
        !await tokensFile.exists() ||
        !await lexiconFile.exists() ||
        !await licenseFile.exists() ||
        await modelFile.length() < _minimumModelBytes) {
      return null;
    }

    final String modelHash = manifest['model_sha256'] as String;
    final String tokensHash = manifest['tokens_sha256'] as String;
    final String lexiconHash = manifest['lexicon_sha256'] as String;
    final String licenseHash = manifest['license_sha256'] as String;
    final String markerValue = _markerValue(
      modelHash,
      tokensHash,
      lexiconHash,
      licenseHash,
    );
    final File marker = File(p.join(dir.path, '.ready_$versionTag'));
    if (await marker.exists() &&
        (await marker.readAsString()).trim() == markerValue) {
      return _paths(
        modelPath,
        tokensPath,
        lexiconPath,
        manifest,
      );
    }

    // One-time migration for older app versions which had already copied the
    // model into app-private storage. Verify large files once, then switch to
    // the new persistent marker instead of asking for the same pack again.
    const List<String> legacyTags = <String>[
      'v3_1_pinned_token_matching',
      'v3_1_pinned_token_matching_v2_integrity',
    ];
    for (final String legacyTag in legacyTags) {
      final File legacyMarker = File(p.join(dir.path, '.ready_$legacyTag'));
      if (!await legacyMarker.exists()) {
        continue;
      }
      final String legacyExpected =
          '$legacyTag|$modelHash|$tokensHash|$lexiconHash|$licenseHash';
      if ((await legacyMarker.readAsString()).trim() != legacyExpected) {
        continue;
      }
      final bool hashesMatch =
          await _sha256File(modelFile) == modelHash &&
          await _sha256File(tokensFile) == tokensHash &&
          await _sha256File(lexiconFile) == lexiconHash;
      if (!hashesMatch) {
        continue;
      }
      await marker.writeAsString(markerValue, flush: true);
      return _paths(modelPath, tokensPath, lexiconPath, manifest);
    }
    return null;
  }

  /// Ensures the model is already installed, returning real file paths required
  /// by sherpa-onnx. Model installation itself is performed by [importFiles].
  Future<ModelPaths> prepare(
    void Function(double progress, String message) onProgress,
  ) async {
    onProgress(0.1, 'جارٍ التحقق من حزمة النموذج المحلية…');
    final ModelPaths? paths = await findInstalled();
    if (paths == null) {
      throw const FormatException(
        'لم يتم تثبيت حزمة النموذج المحلية أو أن ملفاتها غير متوافقة. اختر ملفات حزمة v3.1 من الجهاز.',
      );
    }
    onProgress(1.0, 'النموذج الصوتي المحلي جاهز');
    return paths;
  }

  /// Installs model files selected by the native file picker. Files are copied
  /// with streamed File.copy (no 110 MB model bytes are loaded into Dart memory),
  /// verified against the immutable manifest, then atomically activated.
  Future<ModelPaths> importFiles(
    Map<String, String> selectedPaths, {
    required void Function(double progress, String message) onProgress,
  }) async {
    const List<String> requiredFiles = <String>[
      modelFilename,
      tokensFilename,
      lexiconFilename,
      licenseFilename,
      manifestFilename,
    ];
    final List<String> missing = requiredFiles
        .where((String name) => selectedPaths[name] == null)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw FormatException(
        'حدد الملفات الخمسة كاملة من حزمة النموذج؛ الملفات الناقصة: ${missing.join(', ')}',
      );
    }

    final Directory support = await getApplicationSupportDirectory();
    final Directory destination = Directory(p.join(support.path, 'models'));
    final Directory temporary = Directory(
      p.join(support.path, 'models.importing'),
    );
    final Directory backup = Directory(p.join(support.path, 'models.previous'));
    if (await temporary.exists()) await temporary.delete(recursive: true);
    await temporary.create(recursive: true);

    try {
      for (int index = 0; index < requiredFiles.length; index++) {
        final String name = requiredFiles[index];
        final File source = File(selectedPaths[name]!);
        if (!await source.exists()) {
          throw FormatException('الملف المحدد غير موجود: $name');
        }
        if (name == modelFilename && await source.length() < _minimumModelBytes) {
          throw const FormatException(
            'ملف ONNX أصغر من المتوقع؛ قد يكون تنزيل النموذج غير مكتمل.',
          );
        }
        onProgress(
          (index + 1) / (requiredFiles.length + 1),
          'جارٍ نسخ $name (${index + 1}/${requiredFiles.length})…',
        );
        await source.copy(p.join(temporary.path, name));
      }

      final File manifestFile = File(p.join(temporary.path, manifestFilename));
      final Map<String, dynamic>? manifest = await _readManifest(manifestFile);
      if (manifest == null || !_validManifestMetadata(manifest)) {
        throw const FormatException(
          'manifest غير صالح أو ليس حزمة Quran-Lab v3.1 المتوقعة.',
        );
      }

      onProgress(0.82, 'جارٍ التحقق من بصمات ملفات النموذج…');
      final Map<String, String> expectedHashes = <String, String>{
        modelFilename: manifest['model_sha256'] as String,
        tokensFilename: manifest['tokens_sha256'] as String,
        lexiconFilename: manifest['lexicon_sha256'] as String,
        licenseFilename: manifest['license_sha256'] as String,
      };
      for (final MapEntry<String, String> entry in expectedHashes.entries) {
        final File file = File(p.join(temporary.path, entry.key));
        final String actual = await _sha256File(file);
        if (actual != entry.value) {
          throw FormatException(
            'فشل تحقق SHA-256 للملف ${entry.key}; أعد تنزيل حزمة النموذج كاملة.',
          );
        }
      }
      await _validateTokenFile(File(p.join(temporary.path, tokensFilename)));
      await _validateLexiconFile(File(p.join(temporary.path, lexiconFilename)));

      final String markerValue = _markerValue(
        manifest['model_sha256'] as String,
        manifest['tokens_sha256'] as String,
        manifest['lexicon_sha256'] as String,
        manifest['license_sha256'] as String,
      );
      await File(p.join(temporary.path, '.ready_$versionTag'))
          .writeAsString(markerValue, flush: true);

      if (await backup.exists()) await backup.delete(recursive: true);
      if (await destination.exists()) await destination.rename(backup.path);
      try {
        await temporary.rename(destination.path);
      } catch (_) {
        if (await backup.exists() && !await destination.exists()) {
          await backup.rename(destination.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete(recursive: true);
      onProgress(1.0, 'تم تثبيت النموذج والتحقق من ملفاته');

      final ModelPaths? installed = await findInstalled();
      if (installed == null) {
        throw const FormatException(
          'تم نسخ الملفات لكن لم يجتز النموذج فحص التثبيت النهائي.',
        );
      }
      return installed;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  ModelPaths _paths(
    String modelPath,
    String tokensPath,
    String lexiconPath,
    Map<String, dynamic> manifest,
  ) {
    return ModelPaths(
      modelPath: modelPath,
      tokensPath: tokensPath,
      lexiconPath: lexiconPath,
      modelVersion: manifest['model_version'] as String,
      modelSha256: manifest['model_sha256'] as String,
      tokensSha256: manifest['tokens_sha256'] as String,
      classCount: (manifest['class_count_from_tokens'] as num).toInt(),
      blankId: (manifest['blank_id_from_token_labels'] as num).toInt(),
    );
  }

  String _markerValue(
    String modelHash,
    String tokensHash,
    String lexiconHash,
    String licenseHash,
  ) => '$versionTag|$modelHash|$tokensHash|$lexiconHash|$licenseHash';

  bool _validManifestMetadata(Map<String, dynamic> manifest) {
    final Object? revision = manifest['revision'];
    final String? modelHash = manifest['model_sha256'] as String?;
    final String? tokensHash = manifest['tokens_sha256'] as String?;
    final String? lexiconHash = manifest['lexicon_sha256'] as String?;
    final String? licenseHash = manifest['license_sha256'] as String?;
    bool validHash(String? value) =>
        value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

    final Object? manifestModelFilename =
        manifest['model_filename'] ?? manifest['bundled_model_filename'];
    return manifest['repository'] == _repository &&
        manifestModelFilename == modelFilename &&
        manifest['license_filename'] == licenseFilename &&
        manifest['model_version'] == 'v3.1' &&
        revision is String && RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) &&
        manifest['class_count_from_tokens'] == _expectedClasses &&
        manifest['blank_id_from_token_labels'] == _expectedBlankId &&
        validHash(modelHash) &&
        validHash(tokensHash) &&
        validHash(lexiconHash) &&
        validHash(licenseHash);
  }

  Future<Map<String, dynamic>?> _readManifest(File file) async {
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Invalid/incomplete manifest means the model pack is not ready.
    }
    return null;
  }

  Future<void> _validateTokenFile(File file) async {
    final List<String> lines = await file.readAsLines();
    final Map<int, String> byId = <int, String>{};
    for (final String raw in lines) {
      final String line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final int separator = line.lastIndexOf(RegExp(r'\s'));
      if (separator <= 0 || separator >= line.length - 1) {
        throw const FormatException('صيغة tokens.txt غير صالحة.');
      }
      final String label = line.substring(0, separator).trim();
      final int? id = int.tryParse(line.substring(separator).trim());
      if (label.isEmpty || id == null || id < 0 || byId.containsKey(id)) {
        throw const FormatException('رموز النموذج تحتوي معرّفات غير صالحة أو مكررة.');
      }
      byId[id] = label;
    }
    if (byId.length != _expectedClasses ||
        List<int>.generate(_expectedClasses, (int i) => i)
            .any((int id) => !byId.containsKey(id))) {
      throw const FormatException(
        'يجب أن يحتوي tokens.txt على 251 معرّفًا متصلًا من 0 إلى 250.',
      );
    }
  }

  Future<void> _validateLexiconFile(File file) async {
    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map && decoded is! List) {
        throw const FormatException('صيغة معجم الأصوات غير مدعومة.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('معجم الأصوات ليس JSON صالحًا.');
    }
  }

  Future<String> _sha256File(File file) async {
    final crypto.Digest digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
