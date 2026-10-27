# إصلاح مشكلة QURAN_LAB_REVISION

## لماذا يظهر الخطأ؟

الرسالة `QURAN_LAB_REVISION must be the 40-character commit SHA resolved by the workflow` غير موجودة في نسخة `scripts/fetch_models.py` المصححة. ظهورها في سجل GitHub Actions يعني أن الـ commit الذي يبنيه Actions ما زال يشغّل نسخة قديمة من السكربت، وغالبًا لأن الملفات الجديدة وُضعت داخل مجلد متداخل مثل `rafiq_final_work/scripts/` بدل استبدال `scripts/` في جذر المستودع.

## مسارات الملفات الصحيحة في جذر مستودع GitHub

- `.github/workflows/android_build.yml`
- `scripts/fetch_models.py`
- `scripts/resolve_model_revision.py`
- `test/test_fetch_models.py`

أضف الملفات من حزمة التصحيح إلى هذه المسارات نفسها، ثم أنشئ Commit جديدًا على الفرع الذي يستمع إليه workflow (الافتراضي `main`). لا يكفي إعادة تشغيل workflow القديم قبل دفع الـ commit الجديد.

## ما الذي ستراه بعد الإصلاح؟

الـ workflow الجديد يتأكد أولًا من وجود منطق fallback في `scripts/fetch_models.py`. إذا كان المستودع ما زال يحتوي على الملف القديم، سيتوقف مبكرًا برسالة توضّح أن النسخة القديمة موجودة، بدل الانتظار حتى مرحلة تنزيل النموذج. إذا كان الكود الجديد مستخدمًا لكن `HF_TOKEN` غير صالح، فستظهر رسالة منفصلة توضّح مشكلة الوصول إلى Hugging Face.

## أسرار GitHub المطلوبة

- `HF_TOKEN`: رمز Hugging Face بصلاحية قراءة، مع منح الحساب صلاحية الوصول للنموذج وقبول الشروط المطلوبة.

لا تُلصق الرمز داخل الملفات ولا تطبعه في السجلات.
