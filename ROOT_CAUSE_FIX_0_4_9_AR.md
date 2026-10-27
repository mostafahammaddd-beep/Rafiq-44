# إصلاح رَفِيق 0.4.9 — فشل `flutter analyze` بسبب نسخة قديمة متداخلة

## السبب الحقيقي
أخطاء التحليل الأخيرة كلها (ما عدا ثلاث ملاحظات info) مصدرها مسارات تبدأ بـ `rafiq_final_work/`:

- `rafiq_final_work/lib/features/welcome/welcome_screen.dart:40` يستخدم `FilePicker.platform.pickFiles` (واجهة قديمة غير موجودة في `file_picker` 11.x) ← **الخطأ الوحيد الذي أوقف البناء**.
- بقية التحذيرات (`dart:math` غير مستخدم، `withOpacity`...) من النسخة نفسها القديمة.

أي أن مستودعك يحتوي **مجلدًا فرعيًا `rafiq_final_work/` فيه نسخة قديمة كاملة من المصدر**، و`flutter analyze` يفحص كل المجلدات تحت الجذر. المصدر الحقيقي في الجذر سبق أن أُصلح (`FilePicker.pickFiles`).

## الإصلاح
1. `analysis_options.yaml`: استثناء `rafiq_final_work/**` و`rafiq_v*/**` و`android/**` و`build/**` من التحليل. هذا يعمل **حتى مع workflow قديم** لأن الملف يُقرأ من الجذر.
2. `lib/core/audio_engine/ctc/ctc_types.dart`: إزالة `this.` الزائدة في ثلاثة مواضع `classStride` فقط (ملاحظات info). أُبقي `this.frameStride` عمدًا لأن المعامل `int? frameStride` يظلّل الحقل.
3. الـ workflow يطبع تحذيرًا يسرد أي نسخ متداخلة أخرى لمشروع Flutter.
4. اختبار Python يحمي من عودة المشكلة (الاستثناء في `analysis_options.yaml` وواجهة FilePicker الصحيحة).
5. الإصدار `0.4.9+14` وأسماء artifacts `rafiq-v0.4.9-*`.

## ما يجب عليك فعله أيضًا (الحل النهائي)
احذف المجلد `rafiq_final_work/` من المستودع: افتحه على GitHub ← ⋯ ← Delete directory ← Commit. الاستثناء أعلاه شبكة أمان وليس بديلًا عن النظافة.

## التحقق
- اختبارات Python (21) نجحت محليًا. لا يتوفر `flutter`/`dart` في بيئة إعداد الحزمة؛ نتيجة `flutter analyze` والبناء يؤكدها GitHub Actions فقط.
