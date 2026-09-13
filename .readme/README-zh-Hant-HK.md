<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>AutoJs6 獨立 DEX 編譯插件. 在隔離進程中使用較新的 D8 將腳本 JAR 編譯為 DEX</p>

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
- 繁體中文 (香港) [zh-Hant-HK] # 目前
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
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

AutoJs6 的腳本可以透過 `runtime.loadJar()` 載入 JAR 並呼叫其中的 Java 類別. 由於 Android 無法直接執行 JVM 位元組碼, 這些 JAR 必須先被編譯為 DEX; 預設情況下, 這一步由 AutoJs6 內置的編譯器完成.

本插件提供另一種選擇: 它是一個獨立安裝的應用程式, 在自己的隔離進程中使用較新版本的 Google D8 編譯器完成這步編譯. AutoJs6 把 JAR 交給插件編譯, 取回 DEX 結果後自行驗證, 快取並載入; 插件出現任何問題時, AutoJs6 會自動退回內置編譯器, 腳本通常不受影響.

適合安裝本插件的情況: 希望使用比 AutoJs6 內置版本更新的 D8; 希望編譯過程執行於與 AutoJs6 隔離的進程中; 或希望在不升級 AutoJs6 的情況下單獨升級編譯器.

******

### 運作原理

******

啟用插件後, 一次 `runtime.loadJar()` 呼叫大致經歷以下步驟:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

插件只負責第 3 和第 4 步, 即 "編譯" 本身; 輸入的固定, 結果的驗證, 快取與最終載入始終由 AutoJs6 完成. 雙方透過 Binder 只傳遞檔案描述符, 插件不會讀取腳本目錄, 亦不知道檔案的原始路徑. 編譯結果按輸入內容與編譯參數快取, 相同輸入的重複載入會直接命中快取, 毋須再次編譯.

******

### 功能特性

******

- 編譯由 D8 8.13.22 完成, 插件可獨立於 AutoJs6 更新編譯器版本.
- 編譯執行於插件自己的獨立進程與私人工作區中, 崩潰或失敗不影響 AutoJs6 主進程.
- 雙重核驗: 插件在編譯前核對 JAR 的大小, SHA-256, ZIP 結構與 class 內容; AutoJs6 在編譯後獨立複驗 DEX 輸出.
- 支援 DEBUG 與 RELEASE 編譯模式, multi-dex 輸出, 以及 minApi 24 至 36 的編譯參數.
- 支援 Android 7.0 (API 24) 及以上的所有裝置; API 26+ 使用 D8Command, API 24/25 自動切換至 D8 CLI 相容路徑.
- V1.1 協議支援有序的編譯期 classpath (`runtime.loadJarWithClasspath()`), 用於編譯引用了外部 API 的 JAR.
- 任何失敗都會讓 AutoJs6 至多自動回退一次至內置編譯器, 不會讓腳本卡死在插件上.

******

### 安裝及使用

******

啟用插件共三步: 安裝相容的 AutoJs6, 安裝本插件 APK, 然後在 AutoJs6 開發者選項中手動選擇本插件. 有兩點需要提前了解:

- 插件預設不生效. 僅安裝不會改變 AutoJs6 的任何行為, 必須按下文手動啟用.
- 隨時可以撤銷. 在開發者選項中切回 Built-in D8/dx 即可回復原狀, 毋須解除安裝任何應用程式.

#### 安裝前提

- AutoJs6 build 5270 或更高 (對應 `runtime.loadJar()`); `runtime.loadJarWithClasspath()` 需要更新的配對主程式構建 (驗證時使用 build 5274).
- 主程式與插件必須來自同一可信來源且簽名一致. 簽名不一致時插件無法被選中; 請改用成對發佈的安裝包或成對自行構建, 不要以解除安裝主程式或清除資料的方式繞過.
- 自行構建時保持下方固定的套件名稱與服務組件不變.
- 升級前建議備份腳本與重要資料.

相關標識如下:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 安裝並啟用

1. 安裝或升級至相容版本的 AutoJs6.
2. 安裝本插件 APK.
3. 開啟 AutoJs6, 進入 設定 > 關於應用程式及開發者, 長按應用程式圖示進入開發者選項.
4. 開啟 DEX compiler > Raw JAR compiler provider.
5. 選取本插件的服務組件 (即上方 exact component) 並確認.

再次強調: 僅安裝插件不會自動啟用, AutoJs6 亦不會自動選擇它發現的任何 provider; 第 3 至 5 步是必需的.

#### 確認已生效

回到開發者選項頁面, 當摘要顯示已選擇本插件的服務組件時, 表示啟用成功: 此後腳本中 `runtime.loadJar()` 與 `runtime.loadJarWithClasspath()` 的編譯會優先交給插件處理.

如果清單中找不到本插件, 或摘要仍顯示 Built-in D8/dx, 請依次檢查: AutoJs6 build 是否不低於 5270; 主程式與插件的套件名稱是否與上方一致; 插件應用程式是否被系統停用; 兩者簽名是否一致.

注意: 該摘要表示的是 "目前選擇了誰", 而非 "某次編譯實際由誰完成"; 單次編譯仍可能因快取命中或失敗回退而未經過插件 (見下文).

#### 腳本範例

把包含 JVM `.class` 檔案的 JAR 放到腳本目錄的 `lib/example.jar`, 然後在腳本中如常呼叫 `runtime.loadJar()` 即可; 插件不新增任何新的 JavaScript 全域物件, 腳本寫法與使用內置編譯器時完全相同. 範例中的類別名稱和方法請替換為你的 JAR 中真實存在的 public API.

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

若 JAR 編譯時引用了執行環境中已存在, 但本身不在該 JAR 內的類別 (例如某些 API stub), 可以使用顯式的編譯期 classpath 入口:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

關於 classpath 的三個要點:

- classpath JAR 只在編譯期用於解析引用, 不會打包進輸出, 亦不會被自動載入.
- 若 program 在執行時確實要使用這些類別, 它們必須已存在於最終類別載入器的 parent 鏈中 (如 Android 系統類別或 AutoJs6 自帶類別). 先用 `runtime.loadJar()` 載入依賴 JAR 無法滿足這一點, 那只會建立一個平級的載入器.
- classpath 的宣告順序有意義並參與快取標識; 該入口至少需要傳入一個 classpath JAR.

另外, `.aar` 檔案, 已編譯的 `.dex`, 以及 `defineClass()` 等動態入口始終由 AutoJs6 內置路徑處理, 與本插件無關. 最後請緊記: 編譯不等於安全審查, 只載入你信任的 JAR.

#### 編譯失敗時會發生甚麼

啟用插件後, AutoJs6 依然把 "腳本能跑起來" 放在第一位:

- `runtime.loadJar()`: 插件不可用, 編譯失敗, 逾時或輸出未通過驗證時, AutoJs6 會用同一份 JAR 自動改用內置 D8/dx 編譯, 每次請求至多回退一次.
- `runtime.loadJarWithClasspath()`: 回退同樣至多一次, 且必須帶着完全相同的 program 與 classpath 交給本地 D8 重新編譯; 不會丟棄 classpath, 亦不會靜默降級.
- 你主動取消 (例如停止腳本) 不屬於失敗, 不會觸發回退, 而是直接結束本次載入.
- 插件傳回 BUSY (同一時刻只允許一個編譯工作階段) 時, AutoJs6 按上述規則處理, 稍後重試腳本即可.

因此腳本最終成功執行並不能證明那次編譯經過了插件; 需要確認時請參考下文的排查方法.

#### 排查問題及回報

懷疑插件運作不正常時, 可先切回 Built-in D8/dx 對比行為是否變化. 回報問題時請盡量附上以下資訊:

- AutoJs6 build/版本, 插件版本, 以及開發者選項摘要中的完整組件名稱.
- 裝置型號, Android 版本 (API) 與 CPU 架構 (ABI).
- 觸發問題的 JAR (或其位元組數與 SHA-256), 完整腳本異常資訊與重現步驟.

如果會使用 ADB, 以下命令可收集相關記錄 (`<serial>` 替換為你的裝置序號; 分享前請刪去記錄中的私人路徑與敏感內容):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 停用, 回復及解除安裝

- 暫時停用: 在開發者選項的 Raw JAR compiler provider 中選擇 Built-in D8/dx 並確認, 然後完全結束並重新啟動 AutoJs6. 組件選擇記錄會被保留, 之後可以隨時重新啟用.
- 遇到緊急問題: 按上述方式停用並重啟主程式即可, 毋須解除安裝 AutoJs6, 清除其資料或刪除腳本.
- 解除安裝插件: 先切回 Built-in D8/dx, 再停止 AutoJs6 並解除安裝插件 APK. 解除安裝會清除插件自己的全部資料與暫存檔案; AutoJs6 繼續使用內置編譯器, 不受影響.
- 重新安裝後需要重新手動啟用, 舊的選擇不會自動回復.

******

### 常見問題

******

**問: 安裝插件後腳本沒有任何變化, 是壞了嗎?**

答: 不是. 插件預設關閉, 需要在開發者選項中手動啟用 (見上文); 且它只影響 `runtime.loadJar()` 與 `runtime.loadJarWithClasspath()` 的編譯環節, 不改變腳本的其他行為.

**問: 如何確認某次編譯真的由插件完成?**

答: 開發者選項摘要只表示 "已選擇插件". 由於失敗會自動回退且結果會被快取, 腳本成功不能反推編譯經過插件; 可按 "排查問題及回報" 一節收集記錄確認.

**問: 這個插件能讓腳本跑得更快嗎?**

答: 它的目標是更新的編譯器, 更嚴格的輸入核驗與進程隔離, 而不是效能. 編譯耗時與內置編譯器大體相若, 且已編譯結果會被 AutoJs6 快取.

**問: 插件支援 R8 壓縮/混淆嗎? RELEASE 模式是不是 R8?**

答: 不支援, 也不是. 本插件只做 D8 編譯; `RELEASE` 只是 D8 的 release 編譯模式, 不包含 shrinking, obfuscation 或 mapping. R8 能力屬於另一個獨立的 provider 插件, 不在本插件範圍內.

**問: 為甚麼要求主程式與插件簽名一致?**

答: 這是雙向的安全核驗: 防止其他應用程式冒充 AutoJs6 呼叫插件, 亦防止被竄改的插件冒充編譯服務. 簽名不一致時請更換成對發佈的安裝包, 不要以解除安裝或清除資料繞過.

**問: 插件會連接網絡或讀取我的檔案嗎?**

答: 不會. 插件沒有網絡與儲存權限, 只能透過 AutoJs6 遞來的檔案描述符讀取待編譯內容, 暫存檔案全部位於自己的私人目錄.

******

### 能力邊界

******

為避免誤解, 以下事項明確不屬於本插件的功能範圍:

- 不做 R8 shrinking, optimization, obfuscation, 亦不產生 mapping 檔案; `RELEASE` 僅代表 D8 的 release 編譯模式.
- 不下載或解析依賴 (沒有 Maven/Gradle 整合), 不進行網絡編譯.
- 不處理 `.aar`, 已編譯的 `.dex` 與 `defineClass()` 動態位元組碼, 它們始終走 AutoJs6 內置路徑.
- V1.1 classpath 僅用於編譯, 不打包執行時依賴, 亦不建立組合類別載入器.
- 不承諾位元組級確定性輸出: 相同輸入在不同編譯器版本下可能產生不同但等價的 DEX.
- 不取代 AutoJs6 的輸出驗證: 主程式始終對 DEX 結果作獨立複驗.
- 不會自動成為預設編譯器: 是否啟用始終由使用者顯式控制.

******

### 技術參考

******

以下內容面向需要精確邊界的開發者與整合方; 僅使用插件時通常毋須閱讀.

#### 輸入與輸出

協議 V1.0 透過輸入描述符接收一個 raw program JAR; V1.1 在同一個有界輸入包中接收一個 program JAR 與至少一個有序的編譯期 classpath JAR. 兩者產生相同形式的輸出:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### 插件發現標識

主程式透過以下標識發現並呼叫插件:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

插件聲明 D8 8.13.22, 協議範圍 V1.0 至 V1.1, JAR 輸入, DEX ZIP 輸出, DEBUG 與 RELEASE 模式, minApi 24 至 36 及 multi-dex; runtime library model 為裝置 boot classpath V1.

build 5270 是 V1.0 的最低主程式要求; `runtime.loadJarWithClasspath()` 需要包含 V1.1 支援的配對主程式構建 (代表性驗證使用 build 5274). 插件不含 native library, 以一個純 JVM universal APK 覆蓋所有裝置 ABI.

#### 安全模型

插件不要求網絡與儲存權限. 編譯服務受 `org.autojs.permission.PLUGIN` 權限保護, 每次呼叫都會核驗 AutoJs6 的套件名稱, 呼叫方 UID 歸屬與雙方簽名. 輸入輸出均透過檔案描述符傳遞並在非同步處理前複製, 暫存檔案僅位於插件私人 cache 且會在編譯結束後清理.

#### 資源上限

為防禦惡意或異常輸入, 插件對各環節設置了硬性上限, 超限請求會被直接拒絕:

- 輸入 JAR: 壓縮後最大 64 MiB, 最多 20000 個 entry, 解壓總量最大 256 MiB.
- V1.1 classpath: 最多 32 個 JAR, 單個壓縮後最大 64 MiB, classpath 壓縮總量最大 128 MiB, 整個輸入包最大 256 MiB.
- class 資料: 總量最大 128 MiB, 單個 class 最大 8 MiB; entry 與整體壓縮比另有限制.
- 輸出 DEX ZIP: 最大 16 MiB, 最多 64 個連續編號的 DEX entry; 請求可聲明更低的上限.
- 並發: 同一進程同時只處理一個編譯工作階段, 其餘請求收到可重試的 BUSY 錯誤.
- 診斷資料最多 64 KiB, 錯誤文字與回呼佇列亦有獨立上限.

#### 注意事項

- 取消或關閉會立即阻止結果發佈並中斷 worker, 但 D8 內部的 CPU 計算無法保證立刻停止, 可能在隔離進程中繼續至本次編譯返回.
- 取消後的工作階段槽會保留至 worker 實際退出並完成清理, 期間新請求仍會收到 BUSY.
- 插件不聲明確定性輸出; 快取標識包含編譯器版本與執行時指紋, 版本變化不會誤用舊結果.
- V1.1 只接受主程式凍結打包的編譯期 classpath, 不接收呼叫方檔案路徑或自訂 desugared library 配置.
- 裝置 runtime boot classpath 因系統而異, 請求必須與 provider 報告的 runtime 指紋一致.

******

### 開發路線圖

******

開發按階段推進, R0 至 R5 均已在目前授權邊界內完成並留有可複核證據. R5.2 的有界並行候選仍為 `NOT_PROMOTED`, 因為修正後的三個進程冷啟動快取命中 added P95 延遲格均超過 100 ms. R5.3 凍結了搭載 D8 8.13.22 的 v1.1.0, 並在 API 24/x86、API 34/x86_64 及 API 35/arm64 的代表性真實 provider classpath 格通過; 雙乾淨目錄調查中 54 個產出格的跨目錄輸出摘要差異為 0, 同時維持 `determinismClaim=NOT_CLAIMED`. R5.4 已按 owner 明確決定收口: 獨立 R8 provider 的現有 prerelease 已轉為 non-prerelease Release, 但倉庫繼續保持 Private; 倉庫公開化、配對 AutoJs6 build 5276 的公開發布及官方外掛索引手動登記均未執行, 並整體移交未來獨立 R8 G9 Public Gate. 這不是公開發布, 亦不改變外掛預設關閉狀態. 各條目的完成定義與證據見:

- [查看可勾選的 ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### 版本歷史

******

# v1.1.1

###### 2026/09/13

* `修復` 外掛版本日期固定使用英文, 不隨建置機器的語言變化
* `優化` 統一多語言資源, 明確插件啟用契約並驗證發佈產物

# v1.1.0

###### 2026/09/11

* `提示` `runtime.loadJarWithClasspath()` 需要配對的 AutoJs6 build 5274 或以上版本; 一般 `runtime.loadJar()` 繼續兼容 build 5270 或以上版本
* `新增` 支援 V1.1 有序編譯期 classpath: program JAR 可引用外部 API JAR, classpath 只參與編譯, 不會封裝進 DEX 或自動載入
* `修復` 相容長度宣告一致且在檔案邊界精確結束的標準 ZIP/JAR archive comment, 同時繼續拒絕歧義 EOCD, 長度不一致及尾隨資料
* `修復` 在 Release 壓縮建置中完整保留內嵌 D8 引擎及其服務提供者, 讓正式 APK 可以正常編譯 JAR
* `優化` 提供有界且已脫敏的 D8 info/warning/error 診斷, 包含可用的來源, archive entry 及位置元資料, 方便定位插件編譯失敗
* `優化` 將 D8 內部並行編譯限制為兩個工作線程, 降低大型 JAR 冷編譯的峰值記憶體, 不改變輸出與快取語義
* `優化` 建置階段阻止意外引入原生相依套件, 並輸出 JSON 校驗報告
* `依賴` 升級隨附的 Google R8 程式庫至 8.13.22 (提供 D8 編譯器)

# v1.0.0

###### 2026/08/08

* `提示` 首個正式版本. 安裝後預設不生效, 需在 AutoJs6 開發者選項中手動啟用; 詳細步驟見 README 的 "安裝及使用" 章節
* `新增` 作為 AutoJs6 的外部 DEX 編譯插件: 腳本呼叫 `runtime.loadJar()` 載入 JAR 時, 可由本插件代替內置編譯器完成 JAR 到 DEX 的編譯
* `新增` 編譯在插件獨立進程的私人沙箱中進行, 與 AutoJs6 相互隔離; 插件失敗或不可用時, AutoJs6 至多自動回退一次至內置編譯器
* `新增` 編譯前嚴格核驗輸入 JAR 的大小, SHA-256, ZIP 結構, entry 名稱與 class 內容, 拒絕畸形, 超限或被竄改的輸入
* `新增` 支援 DEBUG 與 RELEASE 編譯模式, multi-dex 輸出與 minApi 24 至 36; 輸出為連續編號的 `classes*.dex` ZIP 並回報實際大小與 SHA-256
* `新增` 相容 Android 7.0 (API 24) 及以上裝置; API 26+ 使用 D8Command, API 24/25 自動使用 D8 CLI 相容路徑
* `新增` 僅與同簽名的 AutoJs6 通訊 (受 `org.autojs.permission.PLUGIN` 權限保護), 不要求網絡與儲存權限
* `新增` 純 JVM 實現, 單個 universal APK 覆蓋所有裝置架構; 附帶 10 種語言的介面, README 與應用程式內說明
* `依賴` 附帶 Google R8 庫 8.13.17 (提供 D8 編譯器)

##### 更多版本

* [CHANGELOG-zh-Hant-HK.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-zh-Hant-HK.md)

******

### 構建

******

```powershell
.\gradlew.bat :app:assembleDebug
```

發佈構建:

```powershell
.\gradlew.bat :app:assembleRelease
```

構建參數來自 `version.properties`. 目前最低 SDK 為 24, 目標 SDK 為 36, 最低 JDK 為 17 且建議 JDK 21.

協議 ABI 由儲存庫 `libs` 目錄中的本地 AAR 提供:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

編譯器透過 Maven 引入 D8 8.13.22. 本地 AAR 只提供穩定的協議邊界, 構建產物是不含 native library 的 universal APK.

******

### 授權條款

******

專案原始碼使用 MPL-2.0. R8 和其他第三方組件繼續適用各自的授權條款.

******

### 資源佈局

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` 從 JSON 來源產生全部 10 種語言的 README 與應用程式內更新記錄; 修改文件請編輯 JSON 來源而非產生的 Markdown. Android 介面字串由各自的資源目錄管理.

******

### 連結

******

- AutoJs6 文件: https://docs.autojs6.com
- R8 專案: https://r8.googlesource.com/r8


[16 KB page alignment and build verification](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/docs/16kb.md)
