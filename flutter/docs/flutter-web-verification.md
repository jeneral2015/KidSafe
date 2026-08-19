# Flutter Guardian Web Verification

- تم بناء `guardian_app` للويب بنجاح في وضع profile باستخدام `flutter build web --profile --no-wasm-dry-run` بتاريخ 2026-08-19.
- أظهرت المعاينة المحلية شاشة تسجيل الدخول العربية الخاصة بـ Flutter Guardian.
- نُشرت مخرجات Flutter Web إلى Firebase Hosting لمشروع `kidsafe-5739d`.
- فتح الرابط `https://kidsafe-5739d.web.app` يعرض تطبيق Flutter بعنوان `guardian_app`، ما يؤكد استبدال واجهة الويب السابقة.
- يلزم تسجيل دخول حساب والد فعلي لفحص بيانات الأطفال الحية وتدفق Firestore داخل الإنتاج؛ وقد اجتازت المكونات الجديدة التحليل والاختبارات الحتمية محلياً.

بعد ظهور شاشة بيضاء في أول نشر profile بسبب تعذر تحميل CanvasKit من CDN في بيئة الاختبار، أُعيد البناء في وضع release مع `--no-web-resources-cdn` ثم أُعيد النشر. يؤكد استخراج محتوى الصفحة من رابط Hosting وجود بيانات Flutter وعنوان KidSafe Guardian في الإصدار الذاتي الاحتواء. يلزم فتح الرابط من متصفح الوالد وتسجيل الدخول لإكمال تحقق العرض التفاعلي للوحة البيانات الحية.
