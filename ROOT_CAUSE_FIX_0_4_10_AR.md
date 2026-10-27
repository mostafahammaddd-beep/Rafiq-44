# إصلاح رَفِيق 0.4.10 — فشل Gradle: `cannot find symbol: class FilePickerPlugin`

## الخطأ في سجلك
```
GeneratedPluginRegistrant.java: error: cannot find symbol
  flutterEngine.getPlugins().add(new com.mr.flutter.plugin.filepicker.FilePickerPlugin());
Execution failed for task ':app:compileReleaseJavaWithJavac'
```
وصل البناء إلى هذه الخطوة بعد نجاح `flutter analyze` و`flutter test`، فالمشكلة في بناء Android وليست في كود Dart.

## السبب الحقيقي
1. مشروع Android يُولَّد في CI بواسطة Flutter 3.47 (AGP 9) ويُبقي `android.builtInKotlin=false`، لأن إضافات مثل `record_android` ما زالت تطبّق Kotlin Gradle Plugin بنفسها (هذا هو تحذير KGP في السجل).
2. إضافة `file_picker` نسخ **10.3.11 وما بعدها و11.x** تتخطى تطبيق Kotlin plugin عند AGP 9 وتفترض أن «Kotlin المدمج» مفعّل.
3. النتيجة: ملفات `FilePickerPlugin.kt` لا تُترجم أبدًا، فلا يجد `GeneratedPluginRegistrant.java` الكلاس.

مصادر: Issue #1973 في مستودع `flutter_file_picker`، ووثائق Flutter «Built-in Kotlin migration» (تفعيل Kotlin المدمج يتطلب Flutter 3.47+ وإضافات مهاجَرة بالكامل)، وتقارير مشاريع حقيقية على Flutter 3.47 + AGP 9.1 عالجت العطل نفسه بالعودة إلى `10.3.10`.

## الإصلاح
- `pubspec.yaml`: `file_picker: 10.3.10` **تثبيت بدقة بلا `^`**. النسخة `10.3.10` تطبّق Kotlin plugin بنفسها فتعمل مع `builtInKotlin=false`. استعمال `^10.3.10` كان سيحلّ إلى نسخة أحدث بها الخلل نفسه.
- `welcome_screen.dart`: العودة إلى واجهة 10.x: `FilePicker.platform.pickFiles(...)`.
- اختبار Python يفرض الثلاثية معًا (التثبيت الدقيق + الواجهة الصحيحة) حتى لا يعيد أحد ترقية الحزمة بالخطأ.
- الإصدار `0.4.10+15` وأسماء artifacts `rafiq-v0.4.10-*`.

## متى يمكن الترقية إلى file_picker أحدث؟
عندما تنتقل كل إضافات المشروع (ومنها `record_android`) إلى Kotlin المدمج ويُفعَّل `android.builtInKotlin=true`، أو عند التأكد من أن نسخة file_picker الأحدث تُترجم Kotlin في وضع `builtInKotlin=false`. جرّب ذلك في فرع منفصل أولًا.

## التحقق
- 22 اختبار Python نجحت محليًا.
- لا يتوفر Flutter ولا Gradle ولا الإنترنت في بيئة إعداد الحزمة، لذلك لم أبنِ APK هنا. التحقق النهائي هو GitHub Actions. تأكدت من وجود `file_picker 10.3.10` على pub.dev ومن أن اعتماديات `win32` وغيرها كما كانت.
