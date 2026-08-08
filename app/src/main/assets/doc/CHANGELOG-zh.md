******

### 版本历史

******

# v1.0.0

###### 2026/08/08

* `新增` DEX Compiler 协议 V1 provider, 插件 ID 和引擎为 `dex-compiler`, provider ID 为 `autojs6-d8`, 变体为 `d8`
* `新增` JAR 到 DEX ZIP 编译, 支持 DEBUG, RELEASE, minApi 24 至 36, multi-dex 及设备 runtime boot classpath 指纹
* `新增` 有界 JAR 大小, entry 数量, 解压数据, class 数据, 诊断和输出, 并严格验证 ZIP framing, 名称及 class magic
* `新增` 仅封装连续 `classes*.dex`, 回报实际大小和 SHA-256, 且由宿主使用 DexIndexedZipValidator 二次验证
* `新增` 单活动会话, 同签名 AutoJs6 调用方核验, 私有临时工作区, API 24 和 25 CLI fallback 及保守取消语义
* `新增` 纯 JVM universal APK, 以及 10 种语言的 README, 更新日志, Android 界面和插件说明
* `依赖` 附加 R8 8.13.17, 用于 D8 编译
