******

### 版本歷史

******

# v1.1.0

###### 2026/08/27

* `提示` `runtime.loadJarWithClasspath()` 需要配對的 AutoJs6 build 5274 或更新版本; 一般 `runtime.loadJar()` 繼續相容 build 5270 或更新版本
* `新增` 支援 V1.1 有序編譯期 classpath: program JAR 可參照外部 API JAR, classpath 只參與編譯, 不會封裝進 DEX 或自動載入
* `修復` 相容長度宣告一致且在檔案邊界精確結束的標準 ZIP/JAR archive comment, 同時繼續拒絕歧義 EOCD, 長度不一致與尾隨資料
* `修復` 在 Release 壓縮建置中完整保留內嵌 D8 引擎及其服務提供者, 讓正式 APK 可以正常編譯 JAR
* `優化` 提供有界且已去識別化的 D8 info/warning/error 診斷, 包含可用的來源, archive entry 與位置中繼資料, 方便定位外掛編譯失敗
* `優化` 將 D8 內部平行編譯限制為兩個工作執行緒, 降低大型 JAR 冷編譯的尖峰記憶體, 不改變輸出與快取語意
* `相依性` 升級隨附的 Google R8 程式庫至 8.13.22 (提供 D8 編譯器)

# v1.0.0

###### 2026/08/08

* `提示` 首個正式版本. 安裝後預設不生效, 需在 AutoJs6 開發者選項中手動啟用; 詳細步驟見 README 的 "安裝與使用" 章節
* `新增` 作為 AutoJs6 的外部 DEX 編譯外掛: 腳本呼叫 `runtime.loadJar()` 載入 JAR 時, 可由本外掛代替內建編譯器完成 JAR 到 DEX 的編譯
* `新增` 編譯在外掛獨立程序的私人沙箱中進行, 與 AutoJs6 相互隔離; 外掛失敗或不可用時, AutoJs6 至多自動回退一次至內建編譯器
* `新增` 編譯前嚴格核驗輸入 JAR 的大小, SHA-256, ZIP 結構, entry 名稱與 class 內容, 拒絕畸形, 超限或被竄改的輸入
* `新增` 支援 DEBUG 與 RELEASE 編譯模式, multi-dex 輸出與 minApi 24 至 36; 輸出為連續編號的 `classes*.dex` ZIP 並回報實際大小與 SHA-256
* `新增` 相容 Android 7.0 (API 24) 及以上裝置; API 26+ 使用 D8Command, API 24/25 自動使用 D8 CLI 相容路徑
* `新增` 僅與同簽章的 AutoJs6 通訊 (受 `org.autojs.permission.PLUGIN` 權限保護), 不要求網路與儲存權限
* `新增` 純 JVM 實作, 單個 universal APK 覆蓋所有裝置架構; 附帶 10 種語言的介面, README 與應用程式內說明
* `相依性` 附帶 Google R8 程式庫 8.13.17 (提供 D8 編譯器)
