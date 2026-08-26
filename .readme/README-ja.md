<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>AutoJs6 向け独立 DEX コンパイラプラグイン. 隔離プロセス内で最新の D8 を使い, スクリプトの JAR を DEX にコンパイル</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 言語

******

README.md は現在以下の言語で利用できます:

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

AutoJs6 のスクリプトは `runtime.loadJar()` で JAR を読み込み, その中の Java クラスを呼び出せます. Android は JVM バイトコードを直接実行できないため, JAR はまず DEX にコンパイルする必要があります; 既定ではこの工程を AutoJs6 内蔵のコンパイラが担当します.

本プラグインはもう一つの選択肢を提供します: 別途インストールするアプリとして, 自身の隔離プロセス内でより新しい Google D8 コンパイラを使ってこのコンパイルを行います. AutoJs6 は JAR をプラグインに渡し, DEX 結果を受け取った後, 自ら検証・キャッシュ・ロードします; プラグインに問題が起きた場合, AutoJs6 は自動的に内蔵コンパイラへ戻るため, スクリプトは通常影響を受けません.

本プラグインが適する場面: AutoJs6 同梱版より新しい D8 を使いたい; コンパイル処理を AutoJs6 から隔離されたプロセスで実行したい; AutoJs6 を更新せずにコンパイラだけを更新したい.

******

### 動作の仕組み

******

プラグインを有効にすると, `runtime.loadJar()` の呼び出しはおおよそ次の手順をたどります:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

プラグインが担当するのは手順 3 と 4, すなわち "コンパイル" そのものだけです; 入力の固定, 結果の検証, キャッシュと最終的なクラスロードは常に AutoJs6 側で行われます. 両アプリは Binder 経由でファイルディスクリプタのみをやり取りするため, プラグインがスクリプトディレクトリを読むことはなく, 元のファイルパスも知り得ません. コンパイル結果は入力内容とコンパイルパラメータに基づいてキャッシュされ, 同じ入力の再ロードは再コンパイルなしでキャッシュにヒットします.

******

### 機能

******

- コンパイルは D8 8.13.22 が実行し, プラグインは AutoJs6 と独立してコンパイラを更新できます.
- コンパイルはプラグイン自身の独立プロセスと私有ワークスペースで実行され, クラッシュや失敗が AutoJs6 本体のプロセスに影響することはありません.
- 二重検証: プラグインはコンパイル前に JAR のサイズ, SHA-256, ZIP 構造, class 内容を照合し, AutoJs6 はコンパイル後に DEX 出力を独立に再検証します.
- DEBUG と RELEASE のコンパイルモード, multi-dex 出力, minApi 24 から 36 のコンパイルパラメータに対応.
- Android 7.0 (API 24) 以上のすべての端末に対応; API 26+ は D8Command を使用し, API 24/25 は自動的に D8 CLI 互換パスへ切り替えます.
- V1.1 プロトコルは順序付きコンパイル時 classpath (`runtime.loadJarWithClasspath()`) に対応し, 外部 API を参照する JAR のコンパイルに使えます.
- いかなる失敗でも AutoJs6 は最大 1 回だけ内蔵コンパイラへフォールバックするため, スクリプトがプラグインで詰まることはありません.

******

### インストールと使い方

******

プラグインの有効化は 3 ステップです: 互換性のある AutoJs6 をインストールし, 本プラグインの APK をインストールし, AutoJs6 の開発者オプションで本プラグインを手動選択します. 先に知っておくべきことが 2 点あります:

- プラグインは既定では無効です. インストールしただけでは AutoJs6 の挙動は何も変わらず, 下記の手順で手動有効化が必要です.
- いつでも元に戻せます. 開発者オプションで Built-in D8/dx に切り替えれば, 何もアンインストールせずに元の挙動へ戻ります.

#### 前提条件

- AutoJs6 build 5270 以上 (`runtime.loadJar()` 用); `runtime.loadJarWithClasspath()` にはより新しいペアのホストビルドが必要です (検証では build 5274 を使用).
- ホストとプラグインは同一の信頼できる提供元から入手し, 署名が一致している必要があります. 署名が一致しない場合プラグインは選択できません; ペアで公開されたパッケージを使うか両方を自分でビルドしてください. ホストのアンインストールやデータ消去で回避しないでください.
- 自分でビルドする場合は, 下記の固定パッケージ名とサービスコンポーネントを変更しないでください.
- アップグレード前にスクリプトと重要なデータのバックアップを推奨します.

関連する識別子は次のとおりです:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### インストールと有効化

1. 互換バージョンの AutoJs6 をインストールまたはアップグレードします.
2. 本プラグインの APK をインストールします.
3. AutoJs6 を開き, 設定 > アプリと開発者について に進み, アプリアイコンを長押しして開発者オプションに入ります.
4. DEX compiler > Raw JAR compiler provider に進みます.
5. 本プラグインのサービスコンポーネント (上記の exact component) を選択して確定します.

重ねて強調します: プラグインをインストールしただけでは有効になりません. AutoJs6 が発見済み provider を自動選択することもないため, 手順 3 から 5 は必須です.

#### 有効化の確認

開発者オプションのページに戻り, サマリーに本プラグインのサービスコンポーネントが選択済みと表示されていれば有効化は成功です: 以後, スクリプトの `runtime.loadJar()` と `runtime.loadJarWithClasspath()` のコンパイルは優先的にプラグインへ渡されます.

一覧に本プラグインが見つからない場合や, サマリーが Built-in D8/dx のままの場合は, 次の順に確認してください: AutoJs6 build が 5270 以上か; ホストとプラグインのパッケージ名が上記と一致するか; プラグインアプリがシステムに無効化されていないか; 両者の署名が一致するか.

注意: このサマリーが示すのは "現在誰が選択されているか" であり, "ある 1 回のコンパイルを実際に誰が行ったか" ではありません; 個々のコンパイルはキャッシュヒットやフォールバックによりプラグインを経由しないことがあります (下記参照).

#### スクリプト例

JVM の `.class` ファイルを含む JAR をスクリプトディレクトリの `lib/example.jar` に置き, いつもどおり `runtime.loadJar()` を呼び出すだけです; プラグインは新しい JavaScript グローバルオブジェクトを一切追加せず, スクリプトの書き方は内蔵コンパイラ使用時とまったく同じです. 例中のクラス名とメソッドは, あなたの JAR に実在する public API に置き換えてください.

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

実行環境には存在するものの JAR 自体には含まれないクラス (API スタブなど) をコンパイル時に参照する場合は, 明示的なコンパイル時 classpath 入口を使えます:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

classpath について知っておくべき 3 点:

- classpath JAR はコンパイル時の参照解決だけに使われ, 出力へは同梱されず, 自動ロードもされません.
- プログラムが実行時にそれらのクラスを実際に使う場合, それらは最終クラスローダの parent チェーン (Android システムクラスや AutoJs6 同梱クラスなど) に既に存在している必要があります. 依存 JAR を先に `runtime.loadJar()` でロードしても兄弟ローダが作られるだけで, この条件は満たせません.
- classpath の宣言順序には意味があり, キャッシュ識別子の一部になります; この入口には少なくとも 1 つの classpath JAR が必要です.

なお, `.aar` ファイル, コンパイル済み `.dex`, `defineClass()` などの動的入口は常に AutoJs6 内蔵パスで処理され, 本プラグインとは無関係です. 最後に, コンパイルはセキュリティ審査ではありません: 信頼できる JAR のみをロードしてください.

#### コンパイル失敗時の挙動

プラグインを有効にしても, AutoJs6 は変わらず "スクリプトが動き続けること" を最優先します:

- `runtime.loadJar()`: プラグインが利用不可, コンパイル失敗, タイムアウト, または出力が検証を通らない場合, AutoJs6 は同じ JAR を内蔵 D8/dx で自動的に再コンパイルします (リクエストごとに最大 1 回).
- `runtime.loadJarWithClasspath()`: フォールバックは同じく最大 1 回で, まったく同一の program と classpath をローカル D8 に渡す必要があります; classpath が破棄されたり, 黙って格下げされたりすることはありません.
- 意図的なキャンセル (スクリプト停止など) は失敗ではありません: フォールバックは発生せず, その読み込みが終了するだけです.
- プラグインが BUSY を返す場合 (同時に 1 つのコンパイルセッションのみ), AutoJs6 は上記ルールに従います; 少し待ってスクリプトを再実行してください.

したがって, スクリプトが最終的に成功しても, そのコンパイルがプラグインを経由した証明にはなりません; 確認が必要な場合は下記の診断手順を使ってください.

#### トラブルシューティングと報告

プラグインの動作が疑わしい場合は, まず Built-in D8/dx に切り替えて挙動を比較してください. 問題を報告する際は, 可能な限り以下の情報を添えてください:

- AutoJs6 の build/バージョン, プラグインのバージョン, 開発者オプションのサマリーに表示される完全なコンポーネント名.
- 端末の機種, Android バージョン (API), CPU アーキテクチャ (ABI).
- 問題を引き起こす JAR (またはそのバイト数と SHA-256), スクリプトの完全な例外情報, 再現手順.

ADB を使える場合, 以下のコマンドで関連ログを収集できます (`<serial>` は端末のシリアル番号に置き換え, 共有前にログ中の私的パスや機微な内容を削除してください):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 無効化, ロールバック, アンインストール

- 一時的な無効化: 開発者オプションの Raw JAR compiler provider で Built-in D8/dx を選択して確定し, AutoJs6 を完全に終了して再起動します. コンポーネントの選択記録は保持されるため, いつでも再有効化できます.
- 緊急時: 上記の手順で無効化してホストを再起動すれば十分です. AutoJs6 のアンインストール, データ消去, スクリプト削除は不要です.
- プラグインのアンインストール: 先に Built-in D8/dx へ切り替え, AutoJs6 を停止してからプラグイン APK をアンインストールします. アンインストールでプラグイン自身のデータと一時ファイルはすべて削除されます; AutoJs6 は内蔵コンパイラで動作し続けます.
- 再インストール後は再び手動での有効化が必要です; 以前の選択は自動復元されません.

******

### よくある質問

******

**Q: プラグインをインストールしたのに何も変わりません. 壊れていますか?**

A: いいえ. プラグインは既定で無効であり, 開発者オプションでの手動有効化が必要です (上記参照); また影響するのは `runtime.loadJar()` と `runtime.loadJarWithClasspath()` のコンパイル工程のみで, スクリプトの他の挙動は変わりません.

**Q: あるコンパイルが本当にプラグインで行われたと確認するには?**

A: 開発者オプションのサマリーは "プラグインが選択されている" ことしか意味しません. 失敗時は自動フォールバックし, 結果はキャッシュされるため, スクリプトの成功からプラグイン経由とは推定できません; "トラブルシューティングと報告" の手順でログを収集して確認してください.

**Q: このプラグインでスクリプトは速くなりますか?**

A: 目的はより新しいコンパイラ, より厳格な入力検証, プロセス隔離であり, 性能ではありません. コンパイル時間は内蔵コンパイラとおおむね同等で, コンパイル結果は AutoJs6 がキャッシュします.

**Q: R8 の圧縮/難読化に対応していますか? RELEASE モードは R8 ですか?**

A: どちらも違います. 本プラグインは D8 コンパイルのみを行います; `RELEASE` は D8 の release コンパイルモードを選ぶだけで, shrinking, obfuscation, mapping は含まれません. R8 の能力は別の独立した provider プラグインの領分です.

**Q: なぜホストとプラグインの署名一致が必要なのですか?**

A: 双方向のセキュリティ検証のためです: 他のアプリが AutoJs6 になりすましてプラグインを呼ぶこと, 改ざんされたプラグインがコンパイルサービスになりすますことを防ぎます. 不一致の場合はペアで公開されたパッケージに切り替えてください. アンインストールやデータ消去での回避はしないでください.

**Q: プラグインはネットワークや私のファイルにアクセスしますか?**

A: しません. プラグインにはネットワーク権限もストレージ権限もなく, AutoJs6 がファイルディスクリプタで渡した内容だけを読み取れます. 一時ファイルはすべて自身の私有ディレクトリ内にあります.

******

### 対応範囲の境界

******

誤解を避けるため, 以下は本プラグインの対応範囲外であることを明示します:

- R8 の shrinking, optimization, obfuscation は行わず, mapping ファイルも生成しません; `RELEASE` は D8 の release コンパイルモードを選ぶだけです.
- 依存関係のダウンロードや解決は行いません (Maven/Gradle 統合なし); ネットワーク経由のコンパイルもしません.
- `.aar` ファイル, コンパイル済み `.dex`, 動的な `defineClass()` バイトコードは扱いません; これらは常に AutoJs6 内蔵パスを通ります.
- V1.1 classpath はコンパイル専用です: 実行時依存を同梱せず, 結合クラスローダも作りません.
- バイトレベルの決定的出力は保証しません: 同じ入力でもコンパイラバージョンが異なれば, 異なるが等価な DEX になり得ます.
- AutoJs6 の出力検証の代替にはなりません: ホストは常に DEX 結果を独立に再検証します.
- 自動的に既定コンパイラになることはありません: 有効化は常にユーザーの明示的な判断です.

******

### 技術リファレンス

******

以下は正確な境界を必要とする開発者と統合担当者向けの内容です; プラグインを使うだけなら通常読む必要はありません.

#### 入力と出力

プロトコル V1.0 は入力ディスクリプタ経由で raw program JAR を 1 つ受け取ります; V1.1 は同じ有界入力バンドル内で program JAR 1 つと順序付きコンパイル時 classpath JAR 1 つ以上を受け取ります. どちらも同じ形式の出力を生成します:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### プラグイン発見識別子

ホストは以下の識別子でプラグインを発見し呼び出します:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

プラグインは D8 8.13.22, プロトコル範囲 V1.0 から V1.1, JAR 入力, DEX ZIP 出力, DEBUG と RELEASE モード, minApi 24 から 36, multi-dex を宣言します; runtime library model は端末の boot classpath V1 です.

build 5270 は V1.0 の最低ホスト要件です; `runtime.loadJarWithClasspath()` には V1.1 対応のペアホストビルドが必要です (代表的検証では build 5274 を使用). プラグインは native library を含まず, 純 JVM の universal APK 1 つで全端末 ABI をカバーします.

#### セキュリティモデル

プラグインはネットワーク権限もストレージ権限も要求しません. コンパイルサービスは `org.autojs.permission.PLUGIN` 権限で保護され, 呼び出しごとに AutoJs6 のパッケージ名, 呼び出し元 UID, 双方の署名を検証します. 入出力はファイルディスクリプタで受け渡しされ非同期処理前に複製されます; 一時ファイルはプラグインの私有 cache のみに置かれ, コンパイル終了後にクリーンアップされます.

#### リソース上限

悪意ある入力や異常入力から防御するため, プラグインは各段階に固定上限を設けており, 超過するリクエストは即座に拒否されます:

- 入力 JAR: 圧縮後最大 64 MiB, entry 最大 20000 個, 展開後合計最大 256 MiB.
- V1.1 classpath: 最大 32 個の JAR, 圧縮後 1 個あたり最大 64 MiB, classpath 圧縮合計最大 128 MiB, 入力バンドル全体最大 256 MiB.
- class データ: 合計最大 128 MiB, 1 class あたり最大 8 MiB; entry ごとと全体の圧縮比にも制限があります.
- 出力 DEX ZIP: 最大 16 MiB, 連番の DEX entry 最大 64 個; リクエスト側でより低い上限を宣言できます.
- 並行性: 1 プロセスにつき同時に 1 つのコンパイルセッションのみ; それ以外のリクエストは再試行可能な BUSY エラーを受け取ります.
- 診断データは最大 64 KiB で, エラーテキストとコールバックキューにも個別の上限があります.

#### 注意事項

- キャンセルやクローズは結果の公開を即座に阻止し worker を中断しますが, D8 内部の CPU 処理は確実には停止できず, 現在のコンパイルが返るまで隔離プロセス内で継続することがあります.
- キャンセル後のセッションスロットは worker が実際に終了しクリーンアップが完了するまで占有され, その間の新規リクエストは BUSY を受け取ります.
- プラグインは決定的出力を宣言しません; キャッシュ識別子にはコンパイラバージョンとランタイム指紋が含まれるため, バージョン変更で古い結果が誤用されることはありません.
- V1.1 はホストが凍結・同梱したコンパイル時 classpath のみを受け付けます; 呼び出し元のファイルパスやカスタム desugared library 設定は受け取りません.
- 端末の runtime boot classpath はシステムにより異なります; リクエストは provider が報告する runtime 指紋と一致する必要があります.

******

### 開発ロードマップ

******

開発は段階的に進行し, R0 から R4 までは検証可能な証跡とともに完了しています. R5 は進行中です: ユーザーガイドとアプリ内説明を改訂し, 上限付きで秘匿化された診断, プロセス内だけの直近経路サマリー, 許可済み Android の失敗/復旧ケースまで完了しました; 独立テスターも「インストール → 有効化 → サンプルスクリプト実行」を問題なく完走しました. R5.2 のベンチマークと数値昇格基準は完了しています. 並列数を制限した候補は combined P95 PSS の 6/6 を通過しましたが, 修正後のプロセスコールド cache-hit added P95 レイテンシ 3 セルすべてが 100 ms を超えたため, まだ昇格していません. V1.1 の実機受け入れ拡大とリリース昇格は未完了です. 各項目の完了定義と証跡はこちら:

- [チェック可能な ROADMAP.md を開く](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### リリース履歴

******

# v1.1.0

###### 2026/08/27

* `ヒント` `runtime.loadJarWithClasspath()` には対応する AutoJs6 build 5274 以降が必要です; 通常の `runtime.loadJar()` は引き続き build 5270 以降と互換です
* `機能` V1.1 の順序付きコンパイル時 classpath に対応: program JAR から外部 API JAR を参照でき, classpath 入力はコンパイルだけに使われて DEX への梱包や自動読み込みは行われません
* `修正` 宣言された長さでファイル末尾に正確に終わる標準の上限付き ZIP/JAR archive comment を受け入れつつ, 曖昧な EOCD, 不整合な長さ, 末尾データは引き続き拒否
* `修正` 難読化された Release ビルドでも組み込み D8 エンジンとサービスプロバイダーを保持し, 本番 APK で JAR 入力をコンパイルできるよう修正
* `改善` 利用可能な source, archive entry, 位置メタデータを含む, 上限付きで機密情報を除去した D8 info/warning/error 診断を提供し, プラグインのコンパイル失敗を調査しやすくしました
* `改善` D8 の内部並列コンパイルを 2 ワーカースレッドに制限し, 出力とキャッシュの意味を変えずに大規模 JAR のコールドコンパイル時ピークメモリを削減
* `依存関係` 同梱の Google R8 ライブラリを 8.13.22 に更新 (D8 コンパイラを提供)

# v1.0.0

###### 2026/08/08

* `ヒント` 初の安定版リリース. インストール後は既定で無効であり, AutoJs6 の開発者オプションで手動有効化が必要です; 手順は README の "インストールと使い方" 章を参照してください
* `機能` AutoJs6 の外部 DEX コンパイラプラグインとして動作: スクリプトが `runtime.loadJar()` で JAR を読み込む際, 内蔵コンパイラの代わりに本プラグインが JAR から DEX へのコンパイルを実行できます
* `機能` コンパイルはプラグイン自身のプロセス内の私有サンドボックスで実行され, AutoJs6 から隔離されます; プラグインが失敗または利用不可の場合, AutoJs6 は最大 1 回だけ内蔵コンパイラへフォールバックします
* `機能` コンパイル前に入力 JAR のサイズ, SHA-256, ZIP 構造, entry 名, class 内容を厳格に検証し, 不正・超過・改ざんされた入力を拒否します
* `機能` DEBUG と RELEASE のコンパイルモード, multi-dex 出力, minApi 24 から 36 に対応; 出力は連番の `classes*.dex` ZIP で, 実際のサイズと SHA-256 を報告します
* `機能` Android 7.0 (API 24) 以上の端末に対応; API 26+ は D8Command を使用し, API 24/25 は自動的に D8 CLI 互換パスを使用します
* `機能` 同一署名の AutoJs6 とのみ通信し (`org.autojs.permission.PLUGIN` 権限で保護), ネットワーク権限もストレージ権限も要求しません
* `機能` 純 JVM 実装で, 単一の universal APK が全端末アーキテクチャをカバー; 10 言語の UI, README, アプリ内説明を同梱
* `依存関係` Google R8 ライブラリ 8.13.17 を同梱 (D8 コンパイラを提供)

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

ビルドパラメータは `version.properties` に由来します. 現在の最低 SDK は 24, ターゲット SDK は 36, 最低 JDK は 17 で JDK 21 を推奨します.

プロトコル ABI はリポジトリ `libs` ディレクトリのローカル AAR が提供します:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

コンパイラは Maven 経由で D8 8.13.22 として導入されます. ローカル AAR は安定したプロトコル境界のみを提供し, ビルド成果物は native library を含まない universal APK です.

******

### ライセンス

******

プロジェクトのソースコードは MPL-2.0 を使用します. R8 とその他のサードパーティコンポーネントには引き続き各自のライセンスが適用されます.

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

`.python/generate_markdown.py` は JSON ソースから全 10 言語の README とアプリ内更新履歴を生成します; ドキュメントを変更する場合は生成済み Markdown ではなく JSON ソースを編集してください. Android の UI 文字列は各リソースディレクトリで管理されます.

******

### リンク

******

- AutoJs6 ドキュメント: https://docs.autojs6.com
- R8 プロジェクト: https://r8.googlesource.com/r8
