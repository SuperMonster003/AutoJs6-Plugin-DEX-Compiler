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
compiler: D8 8.13.17
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

Плагин объявляет D8 8.13.17, ввод JAR, вывод DEX ZIP, режимы DEBUG и RELEASE, minApi от 24 до 36 и multi-dex. Модель runtime library использует boot classpath V1 устройства.

Требуется build хоста 5270 или новее. В плагине нет native library, поэтому один чистый JVM universal APK поддерживает все ABI.

******

### Состояние интеграции с хостом

******

> Текущий DEX adapter AutoJs6 остается experimental функцией, отключенной по умолчанию, и не подключен к AndroidClassLoader. Одна установка плагина не заменяет существующий путь JAR-to-DEX по умолчанию. Для сквозной работы нужен будущий adapter хоста или его явное включение с выбором этого compiler provider.

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

Компилятор использует D8 8.13.17 из Maven. Локальные AAR дают только стабильную границу протокола, результатом является universal APK без native library.

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
