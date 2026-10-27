# إصلاح رَفِيق 0.4.7 — ربط مدقّق اعتماديات التسجيل بسير البناء

## سبب الفشل السابق

كان اختبار `test/test_verify_record_dependencies.py` موجودًا في المستودع، لكنه فشل لأن `.github/workflows/android_build.yml` التي استُخدمت في GitHub Actions لم تكن تستدعي `scripts/verify_record_dependencies.py`. أي أن اختبار التحقق أُضيف من دون خطوة تشغيله في سير العمل المحفوظ في المستودع.

## ما تغيّر

- يضم هذا الإصدار ملف `.github/workflows/android_build.yml` الذي يستدعي `flutter pub deps --json` بعد `flutter pub get` ثم يشغّل `scripts/verify_record_dependencies.py` على الناتج الحقيقي.
- توجد خطوة preflight تتحقق من أن workflow والسكريبت والاختبار موجودة وتوضح الخطأ مبكرًا.
- أصبح اختبار الانحدار يتحقق من أمر التنفيذ نفسه، ومن تصدير JSON، ومن أن الفحص يقع بعد `flutter pub get`، وليس مجرد وجود اسم السكريبت في تعليق.
- رُفع رقم إصدار التطبيق إلى `0.4.7+12`، وتغيّرت أسماء artifact الخاصة بالـ APK إلى `rafiq-v0.4.7-*`.

## تعليمات تطبيق الإصلاح

انسخ محتويات الأرشيف كاملًا إلى **جذر المستودع** مع استبدال الملفات، وتأكد من وجود المسارات التالية مباشرة في الجذر:

- `.github/workflows/android_build.yml`
- `pubspec.yaml`
- `scripts/verify_record_dependencies.py`
- `test/test_verify_record_dependencies.py`

لا تضع المجلدات داخل مجلد متداخل باسم `rafiq_v0_4_7` أو `rafiq_final_work`. ثم ادفع Commit جديدًا وشغّل سير العمل من جديد.

## نطاق التحقق

اختبارات Python تتحقق من صياغة السكربتات وربط مدقّق الحزم بسير العمل. لا تعتبر هذه الاختبارات نجاحًا في بناء Flutter/Android؛ البناء النهائي لا يُؤكّد إلا بعد نجاح GitHub Actions نفسه.
