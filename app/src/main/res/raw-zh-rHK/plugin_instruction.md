# AutoJs6 DEX 編譯器

本插件讓 AutoJs6 在獨立進程中使用 D8 8.13.22 編譯 JAR, 支援 `runtime.loadJar()` 以及 `runtime.loadJarWithClasspath()` 使用的有序編譯期 classpath.

## 啟用前須知

- 插件預設關閉. 僅安裝 APK 不會改變 AutoJs6 的行為.
- 需要 AutoJs6 build 5270 或更高版本, 以及 Android 7.0 (API 24) 或更高版本. classpath 入口需要更新的配對宿主構建.
- AutoJs6 與插件必須具有相同簽名. 簽名不一致的插件無法被選中.

## 啟用插件

1. 安裝或升級相容的 AutoJs6, 然後安裝本插件 APK.
2. 在 AutoJs6 中開啟 設定 > 關於應用與開發者, 長按應用圖示進入開發者選項.
3. 開啟 DEX compiler > Raw JAR compiler provider.
4. 選擇本插件的服務組件並確認.

provider 摘要表示本插件已被選中; 某次載入仍可能直接命中快取, 或使用內置回退.

## 使用與恢復

像平常一樣呼叫 `runtime.loadJar()` 或 `runtime.loadJarWithClasspath()` 即可. 插件不會加入 JavaScript 全域物件, 也無法讀取腳本的原始路徑.

若插件不可用, 正忙, 逾時, 編譯失敗或傳回無效輸出, AutoJs6 會用內置編譯器對同一請求至多重試一次. 主動取消不會觸發回退. 若要停用插件, 請在同一開發者選項頁面選擇 Built-in D8/dx, 然後重新啟動 AutoJs6; 無需解除安裝宿主或清除宿主資料.

## 安全與限制

- 只有相同簽名的 AutoJs6 宿主可以綁定編譯服務.
- 編譯前會檢查輸入大小, SHA-256, ZIP 幀結構, 項目路徑, 壓縮比與 class 檔案; AutoJs6 會在快取或載入前獨立檢查傳回的 DEX ZIP.
- 輸出最大為 16 MiB, 且最多包含 64 個連續的 `classes*.dex` 項目.
- 插件不請求儲存或網絡權限. 它只執行 D8 編譯, 不執行 R8 壓縮或混淆.

回報問題時, 請附上 AutoJs6 build, 插件版本, Android API, 裝置 ABI, 重現步驟與完整腳本錯誤. 分享日誌前請移除私有路徑與敏感內容.
