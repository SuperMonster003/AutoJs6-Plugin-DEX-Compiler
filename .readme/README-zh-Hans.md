<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>独立 DEX 编译插件. 使用 D8 将受验证的 JAR 编译为连续 classes*.dex ZIP</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 语言

******

当前 README.md 支持以下语言:

- 简体中文 [zh-Hans] # 当前
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- [한국어 [ko]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ko.md)
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### 简介

******

DEX Compiler 是 AutoJs6 的独立 DEX Compiler 协议 V1 provider. 它在应用私有工作区中使用 D8 编译经过严格验证的 JVM JAR, 并通过宿主提供的输出描述符返回规范的 DEX ZIP.

******

### 功能

******

- 接受 JAR 输入及 DEBUG 或 RELEASE 模式, 支持 minApi 24 至 36 和 multi-dex 输出.
- 在编译前核验声明的大小和 SHA-256, ZIP framing, entry 名称, class magic, 重复项和解压边界.
- 使用设备 runtime boot classpath 及其指纹编译, 不接受外部 classpath.
- 仅封装连续的 `classes.dex`, `classes2.dex` 等 DEX 文件, 并返回实际 ZIP 大小和 SHA-256.
- Android API 26 及更高版本使用 D8Command, API 24 和 25 使用 D8 CLI fallback.

******

### 输入和输出格式

******

版本 1 仅声明以下编译范围:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### 插件接口

******

宿主通过以下标识发现并调用插件:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

插件声明 D8 8.13.17, JAR 输入, DEX ZIP 输出, DEBUG 和 RELEASE 模式, minApi 24 至 36 及 multi-dex. Runtime library model 为设备 boot classpath V1.

需要宿主构建版本 5270 或更高版本. 插件不含 native library, 因而通过一个纯 JVM universal APK 支持所有设备 ABI.

******

### 宿主集成状态

******

> 当前 AutoJs6 中的 DEX adapter 仍是默认关闭的 experimental 功能, 且尚未接入 AndroidClassLoader. 仅安装本插件不会替换现有 JAR 到 DEX 默认路径. 端到端使用仍需未来提供或由宿主显式启用 adapter 并选择此 compiler provider.

******

### 安全性

******

插件不请求网络或存储权限. 编译服务受 `org.autojs.permission.PLUGIN` 保护, 并核验 AutoJs6 包名, 调用 UID 归属及双方签名. 输入输出描述符在异步处理前复制, 临时文件仅位于应用私有 cache 并在 worker 退出后清理.

******

### 运行限制

******

- 压缩 JAR 最大 64 MiB, 最多 20000 个 entry, 解压总量最大 256 MiB.
- class 数据总量最大 128 MiB, 单个 class 最大 8 MiB. Entry 和整体压缩比均受限制.
- DEX ZIP 最大 16 MiB, 最多 64 个连续编号的 DEX entry. 请求可声明更低的输出上限.
- 同一进程最多有一个活动编译会话. 忙碌请求会返回可重试的 BUSY 错误.
- 诊断数据最多 64 KiB, 错误文本和回调队列也有独立上限.

******

### 限制和注意事项

******

- 取消或关闭会立即阻止结果发布, 关闭描述符并中断 worker, 但 D8 的 CPU 工作无法可靠中断.
- 取消后的会话槽会一直保留到 D8 worker 实际退出并完成清理, 期间新请求仍会收到 BUSY.
- 插件不声明确定性, 不接受外部 classpath 或自定义 desugared library 配置.
- 宿主仍会使用完整的 DexIndexedZipValidator 二次验证输出. 插件的输出封装检查不是宿主验证的替代品.
- 设备 runtime boot classpath 可能因系统而异, 请求必须匹配 provider 报告的 runtime 指纹.

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

##### 更多版本

* [CHANGELOG-zh-Hans.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-zh-Hans.md)

******

### 构建

******

```powershell
.\gradlew.bat :app:assembleDebug
```

发布构建:

```powershell
.\gradlew.bat :app:assembleRelease
```

构建参数来自 `version.properties`. 当前最低 SDK 为 24, 目标 SDK 为 36, 最低 JDK 为 17 且建议 JDK 21.

协议 ABI 由仓库 `libs` 目录中的本地 AAR 提供:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

编译器通过 Maven 使用 D8 8.13.17. 本地 AAR 只提供稳定协议边界, 生成的插件是无 native library 的 universal APK.

******

### 许可证

******

项目源码使用 MPL-2.0. R8 和其他第三方组件继续适用各自的许可证.

******

### 资源布局

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py` 从 JSON 源生成 10 种语言的 README 和应用内更新日志. Android 字符串由各自资源目录管理.

******

### 链接

******

- AutoJs6 文档: https://docs.autojs6.com
- R8 项目: https://r8.googlesource.com/r8
