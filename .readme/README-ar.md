<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>ملحق مستقل لمترجم DEX. ترجمة JAR تم التحقق منه إلى ZIP متصل من classes*.dex باستخدام D8</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### اللغات

******

يدعم README.md الحالي اللغات التالية:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- العربية [ar] # الحالي

******

### مقدمة

******

DEX Compiler هو provider مستقل للإصدار 1 من بروتوكول DEX Compiler في AutoJs6. يستخدم D8 في مساحة عمل خاصة بالتطبيق لترجمة JVM JAR تم التحقق منه بدقة ويعيد DEX ZIP معياريا عبر descriptor إخراج يقدمه المضيف.

******

### الميزات

******

- قبول JAR في وضع DEBUG أو RELEASE مع minApi من 24 إلى 36 وإخراج multi-dex.
- التحقق من الحجم و SHA-256 المعلنين و ZIP framing وأسماء entries و class magic والتكرار وحدود فك الضغط قبل الترجمة.
- الترجمة باستخدام runtime boot classpath للجهاز و fingerprint الخاص به من دون قبول classpath خارجي.
- تغليف `classes.dex` و `classes2.dex` وما يليها فقط بترقيم متصل والإبلاغ عن حجم ZIP و SHA-256 الفعليين.
- استخدام D8Command على Android API 26 والأحدث و D8 CLI fallback على API 24 و 25.

******

### صيغ الإدخال والإخراج

******

يعلن الإصدار 1 نطاق الترجمة التالي فقط:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### واجهة الملحق

******

يكتشف المضيف الملحق ويستدعيه بالهويات التالية:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

يعلن الملحق D8 8.13.17 وإدخال JAR وإخراج DEX ZIP ووضعي DEBUG و RELEASE و minApi من 24 إلى 36 و multi-dex. نموذج runtime library هو boot classpath V1 للجهاز.

يلزم build المضيف 5270 أو أحدث. لا يحتوي الملحق native library ولذلك يدعم ملف universal APK واحد مبني على JVM جميع ABI للأجهزة.

******

### حالة التكامل مع المضيف

******

> يبقى DEX adapter الحالي في AutoJs6 ميزة experimental معطلة افتراضيا وغير متصلة بـ AndroidClassLoader. تثبيت هذا الملحق وحده لا يستبدل مسار JAR-to-DEX الافتراضي الحالي. يتطلب الاستخدام الكامل adapter مستقبليا للمضيف أو تفعيله صراحة مع اختيار هذا compiler provider.

******

### الأمان

******

لا يطلب الملحق إذن الشبكة أو التخزين. الخدمة محمية بواسطة `org.autojs.permission.PLUGIN` وتتحقق من حزمة AutoJs6 وملكية UID المتصل وتطابق التوقيعات. تنسخ descriptors قبل العمل غير المتزامن. تبقى الملفات المؤقتة في cache التطبيق الخاصة وتحذف بعد خروج worker.

******

### حدود التشغيل

******

- يقتصر JAR المضغوط على 64 MiB و 20000 entries مع 256 MiB من البيانات غير المضغوطة إجمالا.
- تقتصر بيانات class على 128 MiB إجمالا و 8 MiB لكل class. تقيد نسب الضغط لكل entry وللأرشيف.
- يقتصر DEX ZIP على 16 MiB و 64 من DEX entries ذات الفهرسة المتصلة. يمكن للطلب اختيار حد إخراج أقل.
- تنشط جلسة ترجمة واحدة فقط في العملية. تتلقى الطلبات المشغولة خطأ BUSY قابلا لإعادة المحاولة.
- تقتصر diagnostics على 64 KiB. لنص الخطأ و callback queue حدود مستقلة.

******

### القيود والتنبيهات

******

- يمنع cancel أو close نشر النتيجة فورا ويغلق descriptors ويقاطع worker, لكن لا يمكن قطع عمل D8 على CPU بشكل موثوق.
- بعد الإلغاء يبقى session slot مشغولا حتى يخرج D8 worker فعليا ويكتمل التنظيف. تتلقى الطلبات الجديدة BUSY في تلك المدة.
- لا يعلن الملحق determinism ولا يقبل classpath خارجيا أو إعداد desugared library مخصصا.
- يعيد المضيف التحقق من الإخراج باستخدام DexIndexedZipValidator الكامل. فحوص التغليف في الملحق لا تستبدل تحقق المضيف.
- قد يختلف runtime boot classpath بحسب النظام. يجب أن يطابق الطلب fingerprint الذي يعلنه provider.

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

##### إصدارات أخرى

* [CHANGELOG-ar.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-ar.md)

******

### البناء

******

```powershell
.\gradlew.bat :app:assembleDebug
```

بناء الإصدار:

```powershell
.\gradlew.bat :app:assembleRelease
```

تأتي المعلمات من `version.properties`. الحد الأدنى SDK هو 24 والهدف SDK هو 36 والحد الأدنى JDK هو 17 ويوصى بـ JDK 21.

تتوفر ABI الخاصة بالبروتوكول من ملفات AAR المحلية في `libs`:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

يستخدم المترجم D8 8.13.17 من Maven. توفر ملفات AAR المحلية حد البروتوكول الثابت فقط والناتج universal APK بلا native library.

******

### الترخيص

******

ينشر مصدر المشروع بموجب MPL-2.0. تبقى R8 والمكونات الخارجية الأخرى خاضعة لتراخيصها.

******

### تخطيط الموارد

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

ينشئ `.python/generate_markdown.py` ملفات README وسجلات changelog داخل التطبيق بعشر لغات من مصادر JSON. تدار سلاسل Android في مجلدات الموارد الخاصة بها.

******

### الروابط

******

- توثيق AutoJs6: https://docs.autojs6.com
- مشروع R8: https://r8.googlesource.com/r8
