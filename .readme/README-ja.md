<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>独立 DEX コンパイラプラグイン. 検証済み JAR を D8 で連続した classes*.dex ZIP にコンパイル</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 言語

******

現在の README.md は次の言語に対応しています:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- 日本語 [ja] # 現在
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### 概要

******

DEX Compiler は AutoJs6 DEX Compiler プロトコル V1 の独立 provider です. アプリ専用ワークスペースの D8 で厳密に検証した JVM JAR をコンパイルし, ホストが提供した出力 descriptor から正規 DEX ZIP を返します.

******

### 機能

******

- DEBUG または RELEASE モードの JAR を受け付け, minApi 24 から 36 と multi-dex 出力に対応します.
- コンパイル前に宣言サイズと SHA-256, ZIP framing, entry 名, class magic, 重複, 展開上限を検証します.
- 外部 classpath を受け付けず, 端末の runtime boot classpath とその fingerprint に対してコンパイルします.
- 連続した `classes.dex`, `classes2.dex` 以降だけを格納し, 実際の ZIP サイズと SHA-256 を返します.
- Android API 26 以降では D8Command, API 24 と 25 では D8 CLI fallback を使用します.

******

### 入力と出力形式

******

バージョン 1 は次のコンパイル範囲だけを宣言します:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### プラグインインターフェース

******

ホストは次の識別情報でプラグインを検出して呼び出します:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

プラグインは D8 8.13.17, JAR 入力, DEX ZIP 出力, DEBUG と RELEASE モード, minApi 24 から 36, multi-dex を宣言します. Runtime library model は端末 boot classpath V1 です.

ホスト build 5270 以降が必要です. Native library を含まないため, 1 個の純 JVM universal APK がすべての端末 ABI に対応します.

******

### ホスト統合状態

******

> runtime.loadJar の raw 経路はデフォルト無効のままで, ホストと同一署名の exact component を明示的に選択する必要があります. production Runtime の single-flight は認証済み key の確定後に有界永続セマンティックキャッシュを使用します. 最後の waiter を含む任意の割り込みはその呼び出し元だけをローカルフォールバックなしで切り離し, producer は完了してキャッシュへ保存できます. last-waiter 協調キャンセルは R2 に残り, safety circuit はプロセス存続中は保守的です. API 31 arm64 の実 provider テストは committed remote dispatch, Binder lifecycle, 指定 DexClassLoader コーパスをカバーし, R1.2 のみ完了しました; R1.1 と複数 API/ABI マトリクスは未完了です.

******

### R1 インストール・利用ガイド

******

> これは既定で無効な R1 の明示的 opt-in 経路であり, インストールだけで有効になる代替コンパイラではありません. R1.3 の複数 API/ABI マトリクスは未完了です. 現在の実 provider の canonical 端末証拠は API 31 arm64 のみなので, minApi 24 から 36 というプロトコル範囲を全端末での受け入れ完了と解釈しないでください.

#### 前提条件

AutoJs6 とプラグインは, 信頼できる組み合わせ済みのリリース元からのみ取得してください. AutoJs6 は build 5270 以降で, ホストとプラグインの現在の完全な署名証明書セットが一致する必要があります. 自分でビルドする場合も下記の固定 package/service identity を維持してください. 更新前にスクリプトと重要なアプリデータをバックアップしてください. Android が署名不一致を示した場合, ホストのアンインストールやデータ消去で回避しないでください.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### インストールして明示的に有効化

最初に互換 AutoJs6 をインストールまたは更新し, 次にプラグイン APK をインストールします. AutoJs6 で 設定 > アプリと開発者について を開き, アプリアイコンを長押しして開発者向けオプションを開きます. DEX compiler > Raw JAR compiler provider で下記の exact component を選び, 確定します. プラグインのインストールだけでは経路は有効にならず, AutoJs6 が発見した provider を自動選択することもありません.

#### 状態の確認

開発者向けオプションに戻り, raw runtime.loadJar JAR が下記 exact component を優先するという要約が明示されていることを確認します. Built-in D8/dx または候補なしの場合, ホスト build、両 package 名、プラグインの有効状態、署名を確認してください. この要約が証明するのは現在の選択と discovery eligibility だけで, 特定のコンパイルが遠隔だったことや R1.3 完了は証明しません.

#### AutoJs6 の例

JVM `.class` を含む読み取り可能な JAR をスクリプト横の `lib/example.jar` に置き, サンプルのクラスとメソッドをその JAR に実在する public API に置き換えます. スクリプトは既存の `runtime.loadJar()` 入口から選択済み provider を使います. プラグインは新しい JavaScript global を追加しません.

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

この例は raw JAR のみです. `.aar`、コンパイル済み `.dex`、互換 helper、動的 `defineClass()` は常にホスト内蔵経路を使います. 検証しても信頼できない bytecode が安全になるわけではありません. 信頼する JAR だけを読み込んでください.

#### 診断情報の収集

問題報告には AutoJs6 build/version、プラグイン version、開発者向けオプションの完全な exact-component 要約、端末 model/API/ABI、入力 JAR の byte 数と SHA-256、発生時刻、完全なスクリプト例外、再現手順を含めてください. ADB を使う場合は各コマンドの `<serial>` に許可された一台の端末 ID を明示し, 障害前後の AndroidClassLoader/AndroidRuntime log を取得して, 共有前に private path、スクリプト内容、その他の機密情報を削除してください.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 無効化と緊急ロールバック

開発者向けオプション > Raw JAR compiler provider で Built-in D8/dx を選択して確定し, AutoJs6 を停止して再起動します. 実験経路は無効になりますが, 後で再選択できるよう component 記録は残ります. 緊急時はまず無効化してホストを再起動してください. AutoJs6 のアンインストール、データ消去、スクリプト削除は不要です. 開いた process safety circuit はその AutoJs6 process が終了するまで意図的に開いたままです.

#### fallback の意味

経路が無効、provider が利用不可または非互換、binding/remote 処理の失敗、timeout、無効な出力、検証済み artifact の採用失敗では, 一回の呼び出しにつきホスト内蔵 D8/dx を最大一回だけ試せます. dispatch 済み Binder 処理は自動 retry しません. 呼び出し元の cancel または thread interruption は local fallback なしで伝播します. AAR、loadDex、defineClass は本プラグインを使いません. したがってスクリプトの最終成功だけでは, 許可された経路のどれかが成功したことしか分からず, プラグインがコンパイルした証拠にはなりません.

#### アンインストールと復旧

まず Built-in D8/dx を選び, 要約で実験が無効になったことを確認してから AutoJs6 を停止し, プラグインをアンインストールします. アンインストールはプラグイン自身のアプリデータと private temporary workspace を永久削除しますが, ホストは内蔵コンパイラを継続利用できます. 復旧時は互換かつ同一署名のプラグインをインストールし, 開発者向けオプションで exact component を再度明示選択してください. 以前の選択が自動的に有効へ戻ると想定しないでください.

#### 既知の制限と受け入れ境界

V1 は bounded raw JVM JAR から DEX ZIP への変換だけを行います. R8 shrinking/obfuscation、外部 classpath、custom desugared library、network compile、deterministic byte output は提供しません. BUSY はホスト fallback につながる場合があり, cancel 後も D8 CPU 処理は cleanup 完了まで isolated process で続くことがあります. API 31 arm64 の R1.2 証拠は R1.1 production fault/rollback gate や API 24/25/26/28/34/36 と x86_64/arm64 の R1.3 matrix を代替しません. これらがチェックされるまでは本ガイドを controlled preview と扱ってください.

******

### 開発ロードマップ

******

R1.2 は 4/4 です: ホスト DEX 16 suites/149 tests, Android-test Kotlin コンパイル, host/test APK assemble が成功し, API 31 arm64 で production concurrency 2 件, 実 lifecycle 2 件, 実 corpus 3 件を個別に通過しました. プローブは provider openSession の直接呼び出しではなく committed remote dispatch を数えます; 独立した重い multi-dex ゲートは 65,700 メソッドを生成し, primary と secondary DEX のクラスをロードしました. 現在の host/test/plugin SHA-256 接頭辞は 181E38E8, 70FAE1E8, 5B6AC53B で, signer は同じ 31a681fc です. R1.1 は 0/7, R1.3 は全項未完了です. R2 は回復スライスのみ開始: process-once strict-canonical janitor は plugin 48/48 と workspace recovery 6/6 を通過し, 最初の Binder 公開前に実際の force-stop 残存 UUID を削除し, 通常 D8 ロード後も workspace を空に保ちました; 他の R2 項目は未チェックです.

- [チェック可能な ROADMAP.md を開く](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### セキュリティ

******

ネットワーク権限とストレージ権限は要求しません. サービスは `org.autojs.permission.PLUGIN` で保護され, AutoJs6 パッケージ名, 呼び出し UID の所有権, 双方の一致する署名を検証します. Descriptor は非同期処理前に複製されます. 一時ファイルはアプリ専用 cache に置かれ, worker 終了後に削除されます.

******

### 動作制限

******

- 圧縮 JAR は 64 MiB と 20000 entries までで, 展開データ合計は 256 MiB までです.
- Class データは合計 128 MiB, 1 class あたり 8 MiB までです. Entry と全体の圧縮率にも上限があります.
- DEX ZIP は 16 MiB と連続 index の DEX entries 64 個までです. リクエストはより低い上限を指定できます.
- プロセス内で有効なコンパイルセッションは 1 つだけです. Busy リクエストには再試行可能な BUSY エラーを返します.
- 診断データは 64 KiB までです. エラー文字列と callback queue にも個別の上限があります.

******

### 制限と注意事項

******

- Cancel または close は結果公開を直ちに禁止し, descriptor を閉じて worker に割り込みますが, D8 の CPU 処理は確実に中断できません.
- キャンセル後も D8 worker が実際に終了して cleanup が完了するまでセッション slot を保持します. その間の新規リクエストは BUSY になります.
- 決定性を宣言せず, 外部 classpath とカスタム desugared library 設定を受け付けません.
- ホストは完全な DexIndexedZipValidator で出力を再検証します. プラグインの packaging 検査はホスト検証の代わりではありません.
- 端末 runtime boot classpath はシステムごとに異なる場合があります. リクエストは provider が報告した fingerprint と一致する必要があります.

******

### リリース履歴

******

# v1.0.0

###### 2026/08/08

* `機能` Plugin ID と engine が `dex-compiler`, provider ID が `autojs6-d8`, variant が `d8` の DEX Compiler プロトコル V1 provider
* `機能` DEBUG, RELEASE, minApi 24 から 36, multi-dex, 端末 runtime boot classpath fingerprint に対応する JAR から DEX ZIP へのコンパイル
* `機能` JAR サイズ, entry 数, 展開データ, class データ, 診断, 出力の上限と厳密な ZIP framing, 名前, class magic 検証
* `機能` 連続 `classes*.dex` の packaging と実サイズおよび SHA-256 の報告, ホスト DexIndexedZipValidator による再検証
* `機能` 単一アクティブセッション, 同一署名 AutoJs6 呼び出し元検証, 専用ワークスペース, API 24 と 25 の CLI fallback, 保守的なキャンセル動作
* `機能` 純 JVM universal APK と 10 言語の README, changelog, Android UI, プラグイン説明
* `依存関係` D8 コンパイル用に R8 8.13.17 を追加

##### その他のリリース

* [CHANGELOG-ja.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-ja.md)

******

### ビルド

******

```powershell
.\gradlew.bat :app:assembleDebug
```

リリースビルド:

```powershell
.\gradlew.bat :app:assembleRelease
```

設定は `version.properties` から取得します. 最小 SDK は 24, ターゲット SDK は 36, 最小 JDK は 17 で JDK 21 を推奨します.

プロトコル ABI は `libs` にあるリポジトリローカル AAR から提供されます:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

コンパイラは Maven の D8 8.13.17 を使用します. ローカル AAR は安定したプロトコル境界だけを提供し, 成果物は native library のない universal APK です.

******

### ライセンス

******

プロジェクトのソースコードは MPL-2.0 です. R8 とその他のサードパーティコンポーネントには各ライセンスが引き続き適用されます.

******

### リソース構成

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` は JSON ソースから 10 言語の README とアプリ内 changelog を生成します. Android 文字列は各リソースディレクトリで管理されます.

******

### リンク

******

- AutoJs6 ドキュメント: https://docs.autojs6.com
- R8 プロジェクト: https://r8.googlesource.com/r8
