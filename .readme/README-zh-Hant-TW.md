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

> raw runtime.loadJar 路由仍預設關閉, 且要求明確選取同簽章 exact component. production Runtime single-flight 在驗證並最終確定 key 後使用有界持久語意快取. 任一 waiter（包括最後一個）中斷都只分離該呼叫端且不執行本機降級; producer 可在背景完成並寫入快取. last-waiter 協同取消留到 R2, 安全熔斷在目前程序生命週期內維持保守. API 31 arm64 真實 provider 已涵蓋 committed remote dispatch、Binder lifecycle 與指定 DexClassLoader 語料, 僅完成 R1.2; R1.1 與多 API/ABI 矩陣仍未完成.

******

### R1 安裝與使用指南

******

> 這是預設關閉的 R1 明確 opt-in 路徑, 並非安裝後自動生效的替代編譯器. R1.3 多 API/ABI 矩陣尚未閉環; 目前真實 provider 的 canonical 裝置證據只涵蓋 API 31 arm64, 因此不可把 minApi 24 至 36 的協定範圍理解為所有裝置均已驗收.

#### 安裝前提

只從可信且配對發佈的來源取得 AutoJs6 與外掛. AutoJs6 必須為 build 5270 或以上, 而主程式與外掛的完整目前簽章憑證集合必須相同; 自行建置時也須保留下列固定套件與服務身分. 升級前請備份腳本與重要應用程式資料. 若 Android 顯示簽章不符, 不要以解除安裝主程式或清除資料繞過.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 安裝並明確啟用

先安裝或升級相容的 AutoJs6, 再安裝外掛 APK. 在 AutoJs6 開啟 設定 > 關於應用程式與開發者, 長按應用程式圖示進入開發者選項; 然後開啟 DEX compiler > Raw JAR compiler provider, 選擇下列 exact component 並確認. 只安裝外掛不會啟用路由, AutoJs6 也不會自動選擇已發現的 provider.

#### 確認狀態

返回開發者選項, 確認摘要明確顯示 raw runtime.loadJar JAR 優先使用下列 exact component. 如只顯示 Built-in D8/dx 或沒有候選項, 請核對主程式 build、兩個套件名稱、外掛啟用狀態與簽章. 摘要只證明目前選擇與發現資格, 不代表某次編譯已使用遠端, 也不代表 R1.3 已完成.

#### AutoJs6 範例

把含 JVM `.class` 的可讀 JAR 放在腳本旁的 `lib/example.jar`, 並把範例類別與方法改為該 JAR 真正存在的 public API. 腳本透過現有 `runtime.loadJar()` 入口使用所選 provider; 外掛不會加入新的 JavaScript global.

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

此範例只涵蓋 raw JAR. `.aar`、已編譯 `.dex`、相容輔助路徑與動態 `defineClass()` 一律保留在主程式內建路徑. 驗證不會讓不可信 bytecode 變安全; 只載入你信任的 JAR.

#### 收集診斷

回報問題時請記錄 AutoJs6 build/版本、外掛版本、開發者選項的完整 exact-component 摘要、裝置型號/API/ABI、輸入 JAR 位元組數與 SHA-256、發生時間、完整腳本例外與重現步驟. 如使用 ADB, 每個指令都要在 `<serial>` 填入唯一已授權裝置, 擷取故障前後的 AndroidClassLoader/AndroidRuntime 日誌, 並在分享前刪除私人路徑、腳本內容與其他敏感資料.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 停用與緊急回復

在開發者選項的 Raw JAR compiler provider 選擇 Built-in D8/dx 並確認, 然後停止與重新啟動 AutoJs6. 這會關閉實驗路由, 但保留已選元件記錄以供日後重新選擇. 緊急回復應先停用並重啟主程式; 不必解除安裝 AutoJs6、清除其資料或刪除腳本. 已開啟的程序安全熔斷會保守地維持至該 AutoJs6 程序結束.

#### 理解 fallback

路由關閉、provider 不可用或不相容、繫結或遠端失敗、逾時、輸出無效或已驗證產物載入失敗時, 每次呼叫最多嘗試一次主程式內建 D8/dx; 已 dispatch 的 Binder 工作不會自動重試. 呼叫方取消或 thread interruption 會直接傳播, 不作本機 fallback. AAR、loadDex 與 defineClass 從不使用本外掛. 因此腳本最終成功只表示某條允許路徑成功, 不能單獨證明外掛完成編譯.

#### 解除安裝與恢復

先選 Built-in D8/dx, 確認摘要顯示實驗已關閉, 再停止 AutoJs6 並解除安裝外掛. 解除安裝會永久刪除外掛本身的應用程式資料與私人暫存工作區, 主程式則可繼續使用內建編譯器. 恢復時安裝相容且同簽章外掛, 重新開啟開發者選項並再次明確選擇 exact component; 不要假設舊選擇會自動重新啟用.

#### 已知限制與驗收邊界

V1 只進行有界 raw JVM JAR 到 DEX ZIP 轉換, 不提供 R8 shrinking/obfuscation、外部 classpath、自訂 desugared library、網路編譯或確定性位元組輸出. BUSY 可觸發主程式 fallback, 取消後 D8 CPU 工作可能在隔離程序繼續至清理完成. API 31 arm64 的 R1.2 證據不能取代 R1.1 production fault/rollback 門禁或 API 24/25/26/28/34/36 與 x86_64/arm64 的 R1.3 矩陣; 在相關項目勾選前應把本指南視為受控預覽.

******

### 開發路線圖

******

R1.2 已達 4/4: 主程式 DEX 16 suites/149 tests 全數通過, Android-test Kotlin 與 host/test APK assemble 成功, API 31 arm64 上 2 個 production concurrency、2 個真實 lifecycle 及 3 個真實 corpus 方法逐項通過. 並行探針統計 committed remote dispatch, 不直接統計 provider openSession; 獨立重型 multi-dex 門禁產生 65,700 個方法並從主要、次要 DEX 載入類別. 目前 host/test/plugin SHA-256 前綴為 181E38E8、70FAE1E8、5B6AC53B, signer 同為 31a681fc. 最終 host/test/plugin 解除安裝均成功, fake provider 保持 absent, 相關程序數為 0. R1.1 維持 0/7, R1.3 全部未勾. R2 僅啟動復原切片: process-once strict-canonical janitor 通過外掛 48/48 與 workspace recovery 6/6, 在首次 Binder 暴露前清除真實 force-stop 舊 UUID, 正常 D8 載入後 workspace 仍為空; R2 其餘項繼續未勾.

- [查看可勾選的 ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

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
