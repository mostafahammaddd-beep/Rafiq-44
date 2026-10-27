# CLAUDE.md — دليل العمل على مشروع رَفِيق

## طريقة العمل (Workflow)

1. Claude **لا يشغّل أوامر `flutter`** في بيئته. ينشئ الملفات برمجياً (Python) ويضغطها في `rafiq_app_stepN.zip`.
2. المستخدم يفك الضغط ويرفع المحتوى إلى **جذر** مستودع GitHub على فرع `main` (يجب أن يظهر `.github/` و`pubspec.yaml` و`lib/` و`scripts/` في الجذر).
3. GitHub Actions (`.github/workflows/android_build.yml`) ينفّذ: استعادة cache للنموذج المثبّت، التحقق/تنزيل مجموعة Quran-Lab v3.1، توليد Android، ترقيع Manifest/Gradle، `flutter pub get`، `dart format`، `flutter analyze`، `flutter test`، ثم APKs منفصلة لـ ARM64 وARM32. لا تعتبر البناء ناجحًا إن لم تُضمّن مجموعة النموذج كاملة.
4. عند فشل البناء يلصق المستخدم سجل الخطأ ونصلحه بأصغر تعديل ممكن.
5. سر المستودع `HF_TOKEN` (Settings → Secrets → Actions) لتحميل النموذج من Quran-Lab.

## قواعد صارمة

- لا أكواد وهمية: يجب تشغيل `flutter analyze` و`flutter test` بعد كل تعديل في بيئة SDK فعلية؛ لا تصف ملفات Dart بأنها سليمة نحويًا قبل تشغيل أدوات التحقق.
- مجلد `android/` **يُولَّد في CI** ولا يُرفق. أي تعديل على الـ Manifest أو Gradle يتم في `scripts/patch_android.py` (يرفع `minSdk` إلى 24 على الأقل و`compileSdk` إلى 35 على الأقل دون خفضهما، ويضيف صلاحيات الميكروفون و`largeHeap`).
- ملفات النموذج (`assets/models/*.onnx` و`tokens.txt` و`quran_phoneme_words.json` وmanifest والرخصة) **لا تُرفع إلى Git**؛ يحمّلها `fetch_models.py` في CI بعد السماح من المصدر الرسمي، ثم يتحقق من بصماتها ونسختها المثبّتة.
- لا يوجد fallback إلى نموذج بديل. `fetch_models.py` يفشل بوضوح إذا لم يتوفر النموذج المثبّت v3.1 أو token table أو المعجم أو الرخصة؛ هذا يمنع APK مضللاً بلا النموذج المطلوب.
- التعديل على ملف موجود: أصغر تعديل ممكن، دون لمس ما لا يخصه.
- الواجهة عربية RTL. لا صلاحية إنترنت ولا تتبّع.
- أي نص قرآني جديد يوضع في `quran_seed.dart` ويُدقَّق على المصحف المطبوع.

## الهوية والإشعارات

- الأيقونات جاهزة في `scripts/android_res/` وتُنسخ في CI؛ لا تُعدَّل `android/` يدوياً.
- `flutter_local_notifications` مثبّتة على `^17.2.2` عمداً: واجهة `zonedSchedule` فيها تتطلب `uiLocalNotificationDateInterpretation` (أُزيل في 18+). الترقية تعني تعديل `reminder_service.dart`.
- المكتبة تتطلب core library desugaring، ويفعّله `patch_android.py`.
- جدولة الإشعارات تستعمل `TZDateTime.utc` من لحظة مطلقة محسوبة بالتوقيت المحلي، فلا حاجة لـ `flutter_timezone`.
- الملف الشخصي في `profile.json` (لا في SQLite) عبر `ProfileRepository`.

## المحرك الصوتي (Isolate)

- `SherpaTajweedEngine` يعمل في Isolate مستقل: `initialize` ثم `beginSession` و`feed` و`updates` و`endSession`. `EngineUpdate` ينقل النص و`tokens` و`timestamps` وزمن الاستدلال ورقم الجلسة/التحديث. لا تستدعِ sherpa من الخيط الرئيسي.
- واجهة `OnlineRecognizerResult` العامة تعرض `text/tokens/timestamps` ولا تعرض raw CTC frame `log_probs`؛ لذلك محرك CTC في `lib/core/audio_engine/ctc/` ليس مربوطًا بالتشغيل المباشر إلى أن يضاف backend حقيقي ومختبر يخرج احتمالات الإطارات.
- لا نمرّر `modelType` (المحرك يُختار من مسار النموذج، وقيمة خاطئة قد تُنهي العملية).
- ملف `engine_init.lock` يمنع حلقة الانهيار؛ لا تحذفه خارج `ModelPrepNotifier`.
- الأحكام: لا نحكم على المد المنفصل والعارض ولا نعد غياب الغنة/الإخفاء حكماً قاطعاً (انظر `tajweed_checker.dart`).

## واجهات مكتبات صارمة

- `record` 5.x: `AudioRecorder().startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1))`.
- الصوت إلى sherpa-onnx: `Float32List` من PCM16 little-endian بالقسمة على `32768.0`.
- `sherpa_onnx`: `initBindings()` داخل عامل النموذج، و`OnlineModelConfig(zipformer2Ctc: ..., tokens, numThreads: 2, provider: 'cpu')`، ثم `OnlineRecognizerConfig(model, feat: FeatureConfig(sampleRate: 16000, featureDim: 80))`. لا تضف `modelType` إلا بعد التحقق من عقد الحزمة وإثبات الحاجة إليه.

## الهيكل المعتمد

```
.
├── .github/workflows/android_build.yml
├── scripts/{patch_android.py, fetch_models.py}
├── assets/models/            # يُملأ في CI
├── PROJECT_SPEC.md  CLAUDE.md  NOTICE.md
├── test/widget_test.dart
└── lib/
    ├── main.dart
    ├── core/
    │   ├── audio_engine/ctc/  # CTC Viterbi/GOP-local/tempo/waqf-wasl typed core
    │   ├── theme/            # الثيم ووضع الليل/النهار
    │   ├── data/             # quran_seed.dart
    │   ├── database/         # sqflite + النماذج + المزودات
    │   ├── tajweed/          # تحليل النص العثماني والأحكام
    │   └── audio_engine/     # نسخ النموذج، الميكروفون، sherpa، المقيّم، المعجم
    └── features/
        ├── welcome/          # شاشة التجهيز (قاعدة البيانات + النموذج)
        ├── home/             # التنقل السفلي
        ├── mushaf/           # فهرس السور وشاشة السورة
        ├── memorize_engine/  # جلسة التلاوة والتسميع (وضعان)
        ├── teacher_dashboard/# الإحصائيات والتقارير
        └── age_modes/        # مؤجَّل
```

## معايير الكود

- Riverpod 2.x: `Notifier` و`NotifierProvider`، وأنواع صريحة.
- `const` حيثما أمكن، وأنواع صريحة للمتغيرات.
- الجلسة الصوتية تُدار بـ `ChangeNotifier` (`RecitationSessionController`) داخل الشاشة.
- تعديل خوارزمية المطابقة في `recitation_evaluator.dart` يرافقه تحديث `test/widget_test.dart`.

## نقاط معروفة للمعايرة

- عتبات القبول: 0.25 مع المعجم، 0.38 مع المولّد التقريبي (في `recitation_session_controller.dart`).
- فك الترميز يجري داخل Isolate مستقل بالفعل. لا تنشئ Isolate لكل chunk؛ أضف الجلسة والمحاذاة داخله أو في عامل مستمر منفصل.
- صيغة `quran_phoneme_words.json` غير موثقة، والمحلل في `phoneme_lexicon_service.dart` متسامح ويتجاهل ما لا يفهمه.
