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
