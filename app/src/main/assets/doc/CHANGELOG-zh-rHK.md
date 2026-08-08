******

### 版本歷史

******

# v1.0.0

###### 2026/08/08

* `新增` DEX Compiler 協議 V1 provider, 插件 ID 和引擎為 `dex-compiler`, provider ID 為 `autojs6-d8`, 變體為 `d8`
* `新增` JAR 到 DEX ZIP 編譯, 支援 DEBUG, RELEASE, minApi 24 至 36, multi-dex 及裝置 runtime boot classpath 指紋
* `新增` 有界 JAR 大小, entry 數量, 解壓資料, class 資料, 診斷和輸出, 並嚴格驗證 ZIP framing, 名稱及 class magic
* `新增` 僅封裝連續 `classes*.dex`, 回報實際大小和 SHA-256, 且由主程式使用 DexIndexedZipValidator 二次驗證
* `新增` 單活動工作階段, 同簽名 AutoJs6 呼叫方核驗, 私人暫存工作區, API 24 和 25 CLI fallback 及保守取消語義
* `新增` 純 JVM universal APK, 以及 10 種語言的 README, 更新日誌, Android 介面和插件說明
* `依賴` 附加 R8 8.13.17, 用於 D8 編譯
