# إصلاح تعارض حزم تسجيل الصوت — رَفِيق 0.4.6

## سبب الفشل

أظهر GitHub Actions أن Dart حلّ هذه المجموعة:

- `record_linux 0.7.2`
- `record_platform_interface 1.6.0`

وهذه المجموعة غير متوافقة: واجهة المنصة تتطلب `startStream(...)` ووسيط `request` في `hasPermission(...)`، بينما `RecordLinux` في `record_linux 0.7.2` لا يطبّقهما.

## الإصلاح

1. ترقية `record` من `^5.2.1` إلى `^6.2.1`، وهو إصدار يدعم Dart 3.5+ وFlutter الحديث، وتتوافق تبعياته مع `record_linux 1.3.x` و`record_platform_interface 1.6.x`.
2. إضافة `scripts/verify_record_dependencies.py`، ليقرأ `flutter pub deps --json` ويفشل قبل التحليل/البناء إذا اختيرت مجموعة غير متوافقة.
3. إضافة اختبارات قبول ورفض للمخطط الصحيح والخاطئ.
4. رفع إصدار التطبيق إلى `0.4.6+11` وتحديث أسماء artifacts.

## تطبيق الإصلاح

في حزمة الإصلاح السريع، فك الضغط **مباشرة فوق جذر مستودع GitHub** مع السماح باستبدال الملفات، ثم commit إلى `main` وشغّل `Rafiq Android APK` من جديد. يجب أن يصبح `pubspec.yaml` في الجذر ويحتوي على `record: ^6.2.1`.

إذا أظهر سجل البناء بعد هذا التعديل نسخة `record_linux 0.7.2`، فغالبًا لم تُرفع التعديلات إلى الجذر الصحيح أو أن workflow يعمل على commit قديم. في النسخة الصحيحة سيطبع فحص الاعتماديات النسخ المختارة، ويوقف CI برسالة صريحة إذا عادت المجموعة غير المتوافقة.

## تحقق متاح

- 18 اختبار Python في حزمة المصدر (اختبارات helper/model/download/configuration/dependency graph).
- فحص صياغة YAML للـ workflow.
- لا تتوفر أداة Flutter/Dart داخل بيئة إعداد الحزمة؛ لذلك لم أزعم أن APK بُني هنا. يجب تأكيد البناء من GitHub Actions.
