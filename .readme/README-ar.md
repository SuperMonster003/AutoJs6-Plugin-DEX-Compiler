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
compiler: D8 8.13.22
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

يعلن الملحق D8 8.13.22 وإدخال JAR وإخراج DEX ZIP ووضعي DEBUG و RELEASE و minApi من 24 إلى 36 و multi-dex. نموذج runtime library هو boot classpath V1 للجهاز.

يلزم build المضيف 5270 أو أحدث. لا يحتوي الملحق native library ولذلك يدعم ملف universal APK واحد مبني على JVM جميع ABI للأجهزة.

******

### حالة التكامل مع المضيف

******

> يبقى مسار raw runtime.loadJar معطلا افتراضيا ويتطلب exact component محددا صراحة ومطابقا للتوقيع. أغلقت R1: ‏R1.1 بنتيجة 7/7 وR1.2 بنتيجة 4/4 ومصفوفة الـ provider الحقيقي canonical بنتيجة 7/7. يستخدم single-flight في Runtime الإنتاجي الـ cache الدلالية الدائمة والمحدودة بعد تثبيت المفتاح الموثق. تفصل مقاطعة أي waiter, بما فيه الأخير, ذلك المستدعي وحده بلا fallback محلي, ويمكن للـ producer الإكمال وحفظ النتيجة. يبقى الإلغاء التعاوني لآخر waiter ضمن R2 وتظل دائرة الأمان محافظة طوال عمر العملية.

******

### دليل تثبيت R1 واستخدامه

******

هذا مسار R1 يتطلب opt-in صريحا وهو معطل افتراضيا، وليس بديلا للمترجم يتفعّل بمجرد التثبيت. يشمل قبول R1 الآن تنفيذ الـ provider الحقيقي على API 24/25/26/28/31/34/36 عبر محاكيات x86_64 وجهاز arm64 فعلي. يغلق ذلك بوابات R1 الثابتة، لكنه لا يفعّل المسار تلقائيا ولا يجعله افتراضيا ولا يوسّع بروتوكول V1 المحدود.

#### المتطلبات المسبقة

احصل على AutoJs6 والملحق فقط من مصدر موثوق يصدرهما كزوج متوافق. يجب أن يكون AutoJs6 من build 5270 أو أحدث، وأن تتطابق المجموعات الكاملة الحالية لشهادات توقيع المضيف والملحق؛ وعند البناء محليا يجب أيضا إبقاء هويات package وservice الثابتة أدناه. انسخ السكربتات وبيانات التطبيق المهمة احتياطيا قبل الترقية. إذا أبلغ Android عن اختلاف التوقيع فلا تتجاوز الفحص بإزالة المضيف أو مسح بياناته.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### التثبيت والتمكين الصريح

ثبّت AutoJs6 المتوافق أو حدّثه أولا، ثم ثبّت APK الملحق. في AutoJs6 افتح الإعدادات > حول التطبيق والمطور واضغط مطولا على أيقونة التطبيق لفتح خيارات المطور. افتح DEX compiler > Raw JAR compiler provider، واختر exact component أدناه ثم أكّد. تثبيت الملحق وحده لا يفعّل المسار، وAutoJs6 لا يختار تلقائيا أي provider تم اكتشافه.

#### تأكيد الحالة

ارجع إلى خيارات المطور وتأكد أن الملخص يذكر صراحة أن ملفات JAR الخام عبر runtime.loadJar تفضّل exact component أدناه. إذا ظهر Built-in D8/dx أو لم يظهر مرشح، فتحقق من build المضيف واسمي package وحالة تمكين الملحق والتواقيع. يثبت الملخص الاختيار الحالي وأهلية الاكتشاف فقط، ولا يثبت أن عملية compile بعينها كانت بعيدة. لا يلغي إغلاق مصفوفة R1 إعادة التحقق من identity والـ handshake والتحقق وقواعد fallback لكل طلب.

#### مثال AutoJs6

ضع ملف JAR قابلا للقراءة يحتوي ملفات JVM `.class` في `lib/example.jar` بجوار السكربت، واستبدل class وmethod في المثال بواجهة public موجودة فعلا في ذلك JAR. يستخدم السكربت provider المختار عبر مدخل `runtime.loadJar()` الحالي؛ ولا يضيف الملحق أي global جديد إلى JavaScript.

```javascript
"use strict";

const jar = files.path("./lib/example.jar");
if (!files.isFile(jar)) {
    throw new Error("Missing JAR: " + jar);
}

runtime.loadJar(jar);

// Replace this with a public class that actually exists in example.jar.
const Example = Packages.com.example.autojs6.DexPluginExample;
console.log("DEX compiler example: " + Example.answer());
```

يغطي المثال ملفات JAR الخام فقط. تبقى ملفات `.aar` و`.dex` المسبقة وcompatibility helpers و`defineClass()` الديناميكي دائما على مسارات المضيف المدمجة. التحقق لا يجعل bytecode غير الموثوق آمنا؛ حمّل ملفات JAR التي تثق بها فقط.

#### جمع التشخيصات

عند الإبلاغ عن مشكلة سجّل build/version لـ AutoJs6 وإصدار الملحق وملخص exact-component الكامل من خيارات المطور وطراز الجهاز/API/ABI وعدد بايتات JAR المدخل وSHA-256 ووقت الحدث والاستثناء الكامل للسكربت وخطوات إعادة المشكلة. عند استخدام ADB ضع معرّف الجهاز الوحيد المصرح به في `<serial>` لكل أمر، والتقط سجلات AndroidClassLoader/AndroidRuntime حول الفشل، واحذف المسارات الخاصة ومحتوى السكربت وأي بيانات حساسة قبل المشاركة.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### التعطيل والتراجع الطارئ

في خيارات المطور > Raw JAR compiler provider اختر Built-in D8/dx وأكّد، ثم أوقف AutoJs6 وأعد تشغيله. يؤدي ذلك إلى إيقاف المسار التجريبي مع الاحتفاظ بسجل component لإعادة اختياره لاحقا. في التراجع الطارئ عطّل المسار أولا وأعد تشغيل المضيف؛ لا حاجة لإزالة AutoJs6 أو مسح بياناته أو حذف السكربتات. يبقى process safety circuit المفتوح مفتوحا عمدا حتى تنتهي عملية AutoJs6 تلك.

#### فهم fallback

عندما يكون المسار معطلا أو provider غير متاح أو غير متوافق، أو يفشل binding أو العمل البعيد، أو يحدث timeout، أو يكون الناتج غير صالح، أو يفشل اعتماد artifact متحقق منه، يمكن للاستدعاء الواحد محاولة D8/dx المدمج في المضيف مرة واحدة كحد أقصى؛ ولا يعاد تلقائيا عمل Binder الذي تم dispatch له. ينتشر إلغاء المستدعي أو thread interruption من دون fallback محلي. لا تستخدم AAR وloadDex وdefineClass هذا الملحق أبدا. لذا نجاح السكربت في النهاية يثبت فقط نجاح مسار مسموح، ولا يثبت أن الملحق أجرى compile.

#### الإزالة والاستعادة

اختر Built-in D8/dx أولا وتأكد من الملخص أن التجربة متوقفة، ثم أوقف AutoJs6 وأزل الملحق. تزيل عملية الإزالة نهائيا بيانات تطبيق الملحق وprivate temporary workspaces الخاصة به، بينما يستطيع المضيف متابعة العمل بالمترجم المدمج. للاستعادة ثبّت ملحقا متوافقا بالتوقيع نفسه، وافتح خيارات المطور واختر exact component صراحة مرة أخرى؛ لا تفترض أن الاختيار القديم سيصبح مفعلا تلقائيا.

#### القيود المعروفة وحدود القبول

ينفذ V1 فقط تحويلا محدودا من raw JVM JAR إلى DEX ZIP. ولا يوفر R8 shrinking/obfuscation أو classpath خارجيا أو desugared library مخصصة أو compile عبر الشبكة أو خرج بايت حتميا. يختار `DexCompilerMode.RELEASE` فقط release compilation mode في D8؛ ولا يفعّل R8 ولا يَعِد بـ shrinking أو optimization أو obfuscation أو mapping. قد تؤدي BUSY إلى fallback لدى المضيف، وقد يستمر عمل D8 على CPU في العملية المعزولة حتى اكتمال التنظيف بعد الإلغاء. يبقى الإلغاء التعاوني بعد مغادرة آخر waiter ضمن R2؛ أما ترقية الأداء والتفعيل الافتراضي وإزالة اعتماد مترجم المضيف فهي خارج R1 المكتملة.

******

### خارطة طريق التطوير

******

أغلقت R1: ‏R1.1 production ‏7/7 وR1.2 automation ‏4/4 ومصفوفة R1.3 الحقيقية 7/7 وشروط الخروج 3/3. نجح API 34 production routing بنتيجة 8/8، وhost DEX ‏16 suites/149 tests وwire ‏4/24 وfake-provider ‏5/25 وplugin ‏48 tests، مع lint ‏0 error. نجحت الحملة canonical ‏f3c2b1af-be93-41e7-b541-f167f90e5cc1 في خلايا الـ provider الحقيقي السبع: API 24/25 عبر CLI وAPI 26/28/34/36 عبر D8Command على x86_64 وAPI 31 على جهاز QV arm64 متعدد المستخدمين. قيمة journal head هي a5abaf62 وrunner SHA-256 هي ca89ac16؛ وتظل الحملات السابقة الفاشلة أو الموقوفة محفوظة. يبقى المسار معطلا افتراضيا، ويبقى إلغاء last-waiter التعاوني والتعافي الأوسع غير مؤشرين ضمن R2.

- [فتح ROADMAP.md ذي قائمة التحقق](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

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

يستخدم المترجم D8 8.13.22 من Maven. توفر ملفات AAR المحلية حد البروتوكول الثابت فقط والناتج universal APK بلا native library.

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
