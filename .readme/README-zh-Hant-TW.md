<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>獨立 DEX 編譯外掛. 使用 D8 將已驗證的 JAR 編譯為連續 classes*.dex ZIP</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 語言

******

目前 README.md 支援以下語言:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- 繁體中文 (台灣) [zh-Hant-TW] # 目前
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### 簡介

******

DEX Compiler 是 AutoJs6 的獨立 DEX Compiler 協定 V1 provider. 它在應用程式私人工作區中使用 D8 編譯經過嚴格驗證的 JVM JAR, 並透過主程式提供的輸出描述元回傳規範 DEX ZIP.

******

### 功能

******

- 接受 JAR 輸入及 DEBUG 或 RELEASE 模式, 支援 minApi 24 至 36 和 multi-dex 輸出.
- 在編譯前核驗宣告的大小和 SHA-256, ZIP framing, entry 名稱, class magic, 重複項和解壓邊界.
- 使用裝置 runtime boot classpath 及其指紋編譯, 不接受外部 classpath.
- 僅封裝連續的 `classes.dex`, `classes2.dex` 等 DEX 檔案, 並回傳實際 ZIP 大小和 SHA-256.
- Android API 26 及更高版本使用 D8Command, API 24 和 25 使用 D8 CLI fallback.

******

### 輸入和輸出格式

******

版本 1 僅宣告以下編譯範圍:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### 外掛介面

******

主程式透過以下識別發現並呼叫外掛:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

外掛宣告 D8 8.13.17, JAR 輸入, DEX ZIP 輸出, DEBUG 和 RELEASE 模式, minApi 24 至 36 及 multi-dex. Runtime library model 為裝置 boot classpath V1.

需要主程式建置版本 5270 或更高版本. 外掛不含 native library, 因而透過一個純 JVM universal APK 支援所有裝置 ABI.

******

### 主程式整合狀態

******

> 目前 AutoJs6 中的 DEX adapter 仍是預設關閉的 experimental 功能, 且尚未接入 AndroidClassLoader. 僅安裝本外掛不會取代現有 JAR 到 DEX 預設路徑. 端到端使用仍需未來提供或由主程式明確啟用 adapter 並選擇此 compiler provider.

******

### 安全性

******

外掛不要求網路或儲存權限. 編譯服務受 `org.autojs.permission.PLUGIN` 保護, 並核驗 AutoJs6 套件名稱, 呼叫 UID 歸屬及雙方簽章. 輸入輸出描述元在非同步處理前複製, 暫存檔案僅位於應用程式私人 cache 並在 worker 結束後清理.

******

### 執行限制

******

- 壓縮 JAR 最大 64 MiB, 最多 20000 個 entry, 解壓總量最大 256 MiB.
- Class 資料總量最大 128 MiB, 單一 class 最大 8 MiB. Entry 和整體壓縮比均受限制.
- DEX ZIP 最大 16 MiB, 最多 64 個連續編號的 DEX entry. 請求可宣告更低的輸出上限.
- 同一程序最多有一個作用中編譯工作階段. 忙碌請求會回傳可重試的 BUSY 錯誤.
- 診斷資料最多 64 KiB, 錯誤文字和回呼佇列也有獨立上限.

******

### 限制和注意事項

******

- 取消或關閉會立即阻止結果發布, 關閉描述元並中斷 worker, 但 D8 的 CPU 工作無法可靠中斷.
- 取消後的工作階段槽會一直保留到 D8 worker 實際結束並完成清理, 期間新請求仍會收到 BUSY.
- 外掛不宣告確定性, 不接受外部 classpath 或自訂 desugared library 配置.
- 主程式仍會使用完整的 DexIndexedZipValidator 二次驗證輸出. 外掛的輸出封裝檢查不是主程式驗證的替代品.
- 裝置 runtime boot classpath 可能因系統而異, 請求必須符合 provider 回報的 runtime 指紋.

******

### 版本歷史

******

# v1.0.0

###### 2026/08/08

* `新增` DEX Compiler 協定 V1 provider, 外掛 ID 和引擎為 `dex-compiler`, provider ID 為 `autojs6-d8`, 變體為 `d8`
* `新增` JAR 到 DEX ZIP 編譯, 支援 DEBUG, RELEASE, minApi 24 至 36, multi-dex 及裝置 runtime boot classpath 指紋
* `新增` 有界 JAR 大小, entry 數量, 解壓資料, class 資料, 診斷和輸出, 並嚴格驗證 ZIP framing, 名稱及 class magic
* `新增` 僅封裝連續 `classes*.dex`, 回報實際大小和 SHA-256, 且由主程式使用 DexIndexedZipValidator 二次驗證
* `新增` 單一作用中工作階段, 同簽章 AutoJs6 呼叫端核驗, 私人暫存工作區, API 24 和 25 CLI fallback 及保守取消語意
* `新增` 純 JVM universal APK, 以及 10 種語言的 README, 更新日誌, Android 介面和外掛說明
* `相依性` 附加 R8 8.13.17, 用於 D8 編譯

##### 更多版本

* [CHANGELOG-zh-Hant-TW.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-zh-Hant-TW.md)

******

### 建置

******

```powershell
.\gradlew.bat :app:assembleDebug
```

發布建置:

```powershell
.\gradlew.bat :app:assembleRelease
```

建置參數來自 `version.properties`. 目前最低 SDK 為 24, 目標 SDK 為 36, 最低 JDK 為 17 且建議 JDK 21.

協定 ABI 由儲存庫 `libs` 目錄中的本機 AAR 提供:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

編譯器透過 Maven 使用 D8 8.13.17. 本機 AAR 只提供穩定協定邊界, 產生的外掛是無 native library 的 universal APK.

******

### 授權

******

專案原始碼使用 MPL-2.0. R8 和其他第三方元件繼續適用各自的授權.

******

### 資源配置

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` 從 JSON 來源產生 10 種語言的 README 和應用程式內更新日誌. Android 字串由各自資源目錄管理.

******

### 連結

******

- AutoJs6 文件: https://docs.autojs6.com
- R8 專案: https://r8.googlesource.com/r8
