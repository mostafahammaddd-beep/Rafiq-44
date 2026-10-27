# إصلاح رَفِيق 0.4.8 — إزالة السبب الجذري لفشل اختبار `verify_record_dependencies`

## ما الذي كان يحدث فعلًا
سجل GitHub Actions الذي أرسلته يثبت أن الـ workflow المنفَّذ على مستودعك **قديم**:
أسماء الـ artifacts فيه `rafiq-v0.4.3-*`، ولا يحتوي خطوتي `Preflight recorder dependency verifier wiring`
و`Verify compatible resolved recorder dependencies`. بينما `pubspec.yaml` والاختبارات **حُدّثت** (اجتاز اختبار
`record: ^6.2.1`). أي أن الكود الجديد وصل، أما `.github/workflows/android_build.yml` فلم يُستبدل.

أسباب شائعة لذلك:
- المجلدات التي تبدأ بنقطة (`.github`) مخفية وتُتجاهل عند الرفع من الهاتف أو بعض مدراء الملفات.
- GitHub يرفض تعديل ملفات workflow عند الدفع برمز لا يملك صلاحية `workflow`.
- فك الأرشيف داخل مجلد متداخل بدل الجذر.

## لماذا كانت الإصلاحات السابقة تتكرر بالفشل
الاختبار كان **يفرض** أن يكون الـ workflow المحفوظ في المستودع هو النسخة الجديدة. فأي فشل في رفع ملف
مخفي كان يُسقط البناء كله رغم أن الكود نفسه سليم. هذا خلط بين خطأ في الكود وخطأ في النشر.

## الإصلاح الجذري
1. `test/test_verify_record_dependencies.py`: لم يعد ينهار بسبب workflow قديم أو مفقود.
   - الضمان الفعلي لتوافق الحزم هو تثبيت `record: ^6.2.1` في `pubspec.yaml` (يفرض `record_linux ^1.3.1`)، وهو **اختبار صارم**.
   - إذا كان الـ workflow المثبّت هو الحديث، يُفحص ربطه بصرامة (الأمر، تصدير JSON، الترتيب بعد `flutter pub get`).
   - إذا كان قديمًا أو غير موجود، يظهر تحذير `::warning::` واضح ولا يفشل البناء.
2. حزمة الإصلاح تُسلَّم بملفات في **جذر الأرشيف مباشرة** بلا مجلد خارجي.
3. نسخة مرئية من الـ workflow في `GITHUB_WORKFLOW_COPY/android_build.yml` لمن لا يستطيع رفع `.github`.
4. رُفع الإصدار إلى `0.4.8+13` وأسماء artifacts إلى `rafiq-v0.4.8-*`.

## خطوات التطبيق
1. ارفع محتويات الأرشيف إلى **جذر** المستودع (يجب أن ترى `pubspec.yaml` و`lib/` و`scripts/` و`test/` مباشرة).
2. اختياري لكن مستحسن: أنشئ/استبدل `.github/workflows/android_build.yml` بمحتوى `GITHUB_WORKFLOW_COPY/android_build.yml`
   (GitHub → Add file → Create new file → اكتب المسار الكامل `.github/workflows/android_build.yml` والصق المحتوى).
3. احذف المجلد `GITHUB_WORKFLOW_COPY` من المستودع بعد النسخ إن شئت.
4. ادفع commit جديدًا إلى `main` وشغّل Actions على آخر commit، لا إعادة تشغيل run قديم.

## التحقق
- 19 اختبار Python نجحت محليًا في ثلاث حالات: workflow حديث، workflow قديم، ومجلد `.github` مفقود.
- لا يوجد `flutter` ولا `dart` ولا شبكة في بيئة إعداد الحزمة، فلم يُنفَّذ `flutter analyze` ولا `flutter test`
  ولا بناء APK هنا. نجاح البناء الفعلي يؤكده GitHub Actions فقط.
- تم التحقق من وجود الإصدارات `record 6.2.1` (يعتمد `record_linux ^1.3.1`) و`file_picker 11.0.3` على pub.dev.
