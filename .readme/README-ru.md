<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>Независимый плагин компилятора DEX. Компиляция проверенного JAR в непрерывный ZIP classes*.dex с D8</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### Языки

******

Текущий README.md поддерживает следующие языки:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- Русский [ru] # текущий
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### Введение

******

DEX Compiler является независимым provider версии 1 протокола DEX Compiler в AutoJs6. Он использует D8 в закрытом рабочем каталоге приложения для компиляции строго проверенного JVM JAR и возвращает канонический DEX ZIP через выходной дескриптор хоста.

******

### Функции

******

- Прием JAR в режиме DEBUG или RELEASE с minApi от 24 до 36 и выводом multi-dex.
- Проверка объявленного размера и SHA-256, framing ZIP, имен entries, magic классов, дубликатов и границ распаковки до компиляции.
- Компиляция с runtime boot classpath устройства и его fingerprint без внешнего classpath.
- Упаковка только непрерывных `classes.dex`, `classes2.dex` и следующих DEX с возвратом фактических размера ZIP и SHA-256.
- D8Command на Android API 26 и новее и fallback CLI D8 на API 24 и 25.

******

### Форматы ввода и вывода

******

Версия 1 объявляет только следующую область компиляции:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

******

### Интерфейс плагина

******

Хост обнаруживает и вызывает плагин со следующими идентификаторами:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

Плагин объявляет D8 8.13.22, ввод JAR, вывод DEX ZIP, режимы DEBUG и RELEASE, minApi от 24 до 36 и multi-dex. Модель runtime library использует boot classpath V1 устройства.

Требуется build хоста 5270 или новее. В плагине нет native library, поэтому один чистый JVM universal APK поддерживает все ABI.

******

### Состояние интеграции с хостом

******

> Путь raw runtime.loadJar остается отключенным по умолчанию и требует явно выбранного exact component с той же подписью. R1 закрыт: R1.1 7/7, R1.2 4/4 и каноническая матрица реального provider 7/7. Production Runtime single-flight использует ограниченный постоянный семантический кэш после аутентифицированной финализации ключа. Прерывание любого waiter, включая последнего, отделяет только этого вызывающего без локального fallback; producer может завершиться и заполнить кэш. Кооперативная отмена последнего waiter остается в R2, а защитный circuit сохраняет консервативное состояние до конца жизни процесса.

******

### Руководство по установке и использованию R1

******

Это явно включаемый путь R1, по умолчанию отключенный, а не замена компилятора, которая активируется сразу после установки. Приемка R1 теперь включает реальный provider на API 24/25/26/28/31/34/36, эмуляторах x86_64 и физическом устройстве arm64. Это закрывает фиксированные gates R1, но не включает путь автоматически, не делает плагин вариантом по умолчанию и не расширяет ограниченный протокол V1.

#### Предварительные условия

Получайте AutoJs6 и плагин только из доверенного источника парных выпусков. Требуется AutoJs6 build 5270 или новее, а полные текущие наборы сертификатов подписи хоста и плагина должны совпадать; при собственной сборке также сохраняйте фиксированные package и service identity ниже. Перед обновлением создайте резервную копию скриптов и важных данных приложения. Если Android сообщает о несовпадении подписи, не обходите проверку удалением хоста или очисткой его данных.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### Установка и явное включение

Сначала установите или обновите совместимый AutoJs6, затем установите APK плагина. В AutoJs6 откройте Настройки > О приложении и разработчике и удерживайте значок приложения, чтобы открыть параметры разработчика. Откройте DEX compiler > Raw JAR compiler provider, выберите exact component ниже и подтвердите. Одна установка плагина не включает маршрут, а AutoJs6 никогда автоматически не выбирает найденный provider.

#### Проверка состояния

Вернитесь в параметры разработчика и убедитесь, что сводка явно сообщает: raw JAR для runtime.loadJar предпочитают exact component ниже. Если указано Built-in D8/dx или кандидата нет, проверьте build хоста, оба имени package, состояние плагина и подписи. Сводка подтверждает только текущий выбор и право на обнаружение; она не доказывает, что конкретная компиляция была удаленной. Завершение матрицы R1 не отменяет повторную проверку identity, handshake, валидацию и правила fallback для каждого запроса.

#### Пример AutoJs6

Поместите читаемый JAR с JVM-файлами `.class` в `lib/example.jar` рядом со скриптом и замените пример класса и метода на реально существующий public API этого JAR. Скрипт использует выбранный provider через существующий вход `runtime.loadJar()`; плагин не добавляет новый глобальный объект JavaScript.

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

Пример относится только к raw JAR. `.aar`, заранее скомпилированные `.dex`, compatibility helper и динамический `defineClass()` всегда остаются на встроенных путях хоста. Проверка не делает недоверенный bytecode безопасным; загружайте только доверенные JAR.

#### Сбор диагностики

При сообщении о проблеме запишите build/version AutoJs6, версию плагина, полную сводку exact-component из параметров разработчика, модель/API/ABI устройства, размер в байтах и SHA-256 входного JAR, время события, полное исключение скрипта и шаги воспроизведения. При использовании ADB укажите единственное разрешенное устройство в `<serial>` каждой команды, соберите журналы AndroidClassLoader/AndroidRuntime около сбоя и перед публикацией удалите приватные пути, содержимое скрипта и другие чувствительные данные.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### Отключение и аварийный откат

В Параметры разработчика > Raw JAR compiler provider выберите Built-in D8/dx и подтвердите, затем остановите и перезапустите AutoJs6. Экспериментальный маршрут отключится, но запись выбранного component останется для повторного выбора. При аварийном откате сначала отключите маршрут и перезапустите хост; удалять AutoJs6, очищать его данные или удалять скрипты не требуется. Открытый process safety circuit намеренно остается открытым до завершения этого процесса AutoJs6.

#### Как работает fallback

Если маршрут отключен, provider недоступен или несовместим, binding или удаленная работа завершились ошибкой, истек timeout, вывод недействителен либо не удалось принять проверенный artifact, один вызов может сделать не более одной попытки встроенного D8/dx хоста; уже dispatch-работа Binder автоматически не повторяется. Отмена вызывающей стороны или thread interruption распространяется без локального fallback. AAR, loadDex и defineClass никогда не используют этот плагин. Поэтому итоговый успех скрипта доказывает лишь успех одного разрешенного пути, но не компиляцию плагином.

#### Удаление и восстановление

Сначала выберите Built-in D8/dx и убедитесь по сводке, что эксперимент отключен, затем остановите AutoJs6 и удалите плагин. Удаление навсегда стирает собственные данные приложения и приватные временные workspace плагина; хост может продолжить работу со встроенным компилятором. Для восстановления установите совместимый плагин с той же подписью, вновь откройте параметры разработчика и явно выберите exact component. Не предполагайте, что старый выбор включится автоматически.

#### Известные ограничения и граница приемки

V1 выполняет только ограниченное преобразование raw JVM JAR в DEX ZIP. Нет R8 shrinking/obfuscation, внешнего classpath, собственной desugared library, сетевой компиляции и детерминированного побайтового вывода. `DexCompilerMode.RELEASE` выбирает только release compilation mode D8; он не включает R8 и не обещает shrinking, optimization, obfuscation или mapping. BUSY может привести к fallback хоста, а CPU-работа D8 после отмены может продолжаться в изолированном процессе до очистки. Кооперативная отмена после ухода последнего waiter остается в R2; повышение производительности, включение по умолчанию и удаление зависимостей компилятора хоста находятся вне завершенного R1.

******

### План развития

******

R1 закрыт: R1.1 production 7/7, R1.2 automation 4/4, R1.3 матрица реальных устройств 7/7 и условия выхода 3/3. API 34 production routing прошел 8/8; host DEX 16 suites/149 tests, wire 4/24, fake-provider 5/25 и plugin 48 tests прошли, lint 0 error. Каноническая campaign f3c2b1af-be93-41e7-b541-f167f90e5cc1 прошла все семь ячеек реального provider: API 24/25 CLI, API 26/28/34/36 D8Command на x86_64 и API 31 на многопользовательском устройстве QV arm64. journal head a5abaf62, runner SHA-256 ca89ac16; предыдущие неудачные или остановленные campaigns сохранены. Путь остается отключенным по умолчанию, а кооперативная отмена последнего waiter и широкое восстановление остаются непомеченными в R2.

- [Открыть ROADMAP.md с контрольным списком](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### Безопасность

******

Плагин не запрашивает разрешения сети или хранилища. Служба защищена `org.autojs.permission.PLUGIN` и проверяет пакет AutoJs6, принадлежность вызывающего UID и совпадение подписей. Дескрипторы дублируются до асинхронной работы. Временные файлы находятся в закрытом cache и удаляются после выхода worker.

******

### Рабочие ограничения

******

- Сжатый JAR ограничен 64 MiB и 20000 entries, общий объем распаковки ограничен 256 MiB.
- Данные классов ограничены 128 MiB всего и 8 MiB на класс. Коэффициенты сжатия entry и архива ограничены.
- DEX ZIP ограничен 16 MiB и 64 непрерывно индексированными DEX entries. Запрос может выбрать меньший предел.
- В процессе активен не более одного сеанса компиляции. Занятые запросы получают повторяемую ошибку BUSY.
- Диагностика ограничена 64 KiB. Текст ошибки и очередь callbacks имеют отдельные пределы.

******

### Ограничения и примечания

******

- Cancel или close сразу запрещает публикацию, закрывает дескрипторы и прерывает worker, но работу D8 на CPU нельзя надежно прервать.
- После отмены slot занят до фактического выхода worker D8 и завершения очистки. Новые запросы тем временем получают BUSY.
- Плагин не заявляет детерминизм и не принимает внешний classpath или пользовательскую конфигурацию desugared library.
- Хост повторно проверяет вывод полным DexIndexedZipValidator. Проверки упаковки в плагине не заменяют проверку хоста.
- Runtime boot classpath может отличаться в разных системах. Запрос должен совпадать с fingerprint от provider.

******

### История выпусков

******

# v1.0.0

###### 2026/08/08

* `Функция` Provider протокола DEX Compiler V1 с ID и движком `dex-compiler`, provider ID `autojs6-d8` и вариантом `d8`
* `Функция` Компиляция JAR в DEX ZIP с DEBUG, RELEASE, minApi от 24 до 36, multi-dex и fingerprint runtime boot classpath устройства
* `Функция` Ограничения размера JAR, entries, распакованных данных, классов, диагностики и вывода со строгой проверкой framing ZIP, имен и magic классов
* `Функция` Непрерывная упаковка `classes*.dex` с фактическими размером и SHA-256 и повторной проверкой хоста через DexIndexedZipValidator
* `Функция` Один активный сеанс, проверка подписи вызывающего AutoJs6, закрытая рабочая область, fallback CLI на API 24 и 25 и осторожная отмена
* `Функция` Один чистый JVM universal APK с README, changelog, интерфейсом Android и инструкциями плагина на 10 языках
* `Зависимость` Добавлен R8 8.13.17 для компиляции D8

##### Другие выпуски

* [CHANGELOG-ru.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-ru.md)

******

### Сборка

******

```powershell
.\gradlew.bat :app:assembleDebug
```

Релизная сборка:

```powershell
.\gradlew.bat :app:assembleRelease
```

Параметры берутся из `version.properties`. Минимальный SDK 24, целевой SDK 36, минимальный JDK 17, рекомендуется JDK 21.

ABI протокола предоставляется локальными AAR репозитория в `libs`:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

Компилятор использует D8 8.13.22 из Maven. Локальные AAR дают только стабильную границу протокола, результатом является universal APK без native library.

******

### Лицензия

******

Исходный код проекта распространяется по MPL-2.0. R8 и другие сторонние компоненты сохраняют свои лицензии.

******

### Структура ресурсов

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` создает README и встроенные changelog на 10 языках из JSON. Строки Android находятся в собственных каталогах ресурсов.

******

### Ссылки

******

- Документация AutoJs6: https://docs.autojs6.com
- Проект R8: https://r8.googlesource.com/r8
