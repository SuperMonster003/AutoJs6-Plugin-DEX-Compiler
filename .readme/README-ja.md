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

> 現在の AutoJs6 DEX adapter はデフォルト無効の experimental 機能のままで, AndroidClassLoader に接続されていません. このプラグインをインストールするだけでは既存のデフォルト JAR-to-DEX 経路は置き換わりません. End-to-end 利用には将来の host adapter, またはホストによる明示的な有効化とこの compiler provider の選択が必要です.

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
