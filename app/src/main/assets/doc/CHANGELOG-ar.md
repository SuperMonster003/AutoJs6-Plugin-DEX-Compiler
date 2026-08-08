******

### سجل الإصدارات

******

# v1.0.0

###### 2026/08/08

* `ميزة` Provider لبروتوكول DEX Compiler V1 بمعرف ومحرك `dex-compiler` و provider ID هو `autojs6-d8` ومتغير `d8`
* `ميزة` ترجمة JAR إلى DEX ZIP مع DEBUG و RELEASE و minApi من 24 إلى 36 و multi-dex و fingerprint للـ runtime boot classpath في الجهاز
* `ميزة` حدود لحجم JAR وعدد entries والبيانات المفكوكة وبيانات class و diagnostics والإخراج مع تحقق صارم من ZIP framing والأسماء و class magic
* `ميزة` تغليف متصل لـ `classes*.dex` مع الحجم و SHA-256 الفعليين وإعادة تحقق المضيف عبر DexIndexedZipValidator
* `ميزة` جلسة نشطة واحدة وفحص متصل AutoJs6 ذي التوقيع نفسه ومساحة خاصة و CLI fallback على API 24 و 25 وإلغاء محافظ
* `ميزة` ملف universal APK واحد مبني على JVM مع README و changelog وواجهة Android وتعليمات الملحق بعشر لغات
* `تبعية` إضافة R8 8.13.17 لترجمة D8
