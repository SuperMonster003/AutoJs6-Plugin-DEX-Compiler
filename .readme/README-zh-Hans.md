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

> raw runtime.loadJar 路由仍默认关闭, 且要求显式选择同签名 exact component. production Runtime single-flight 在认证并最终化 key 后使用有界持久语义 cache. 任一 waiter（包括最后一个）中断都只分离该调用方且不作本地回退; producer 可在后台完成并写入 cache. last-waiter 协作取消留到 R2, 安全熔断在当前进程生命周期内保持保守. API 31 arm64 真实 provider 已覆盖 committed remote dispatch、Binder lifecycle 与指定 DexClassLoader 语料, 仅完成 R1.2; R1.1 与多 API/ABI 矩阵仍未完成.

******

### R1 安装与使用指南

******

> 这是默认关闭的 R1 显式 opt-in 路径, 不是安装后自动生效的替代编译器. R1.3 多 API/ABI 矩阵尚未闭环; 当前真实 provider 的 canonical 设备证据仅覆盖 API 31 arm64, 因而不得把 minApi 24 至 36 的协议范围误当成全部设备已验收.

#### 安装前提

只从可信且成对发布的来源取得 AutoJs6 与插件. AutoJs6 必须为 build 5270 或更高, 且宿主与插件的完整当前签名证书集合必须相同; 自行构建时也必须保留下面的固定包名和服务组件. 升级前备份脚本与重要应用数据. 若 Android 报签名不匹配, 不要通过卸载宿主或清除数据来绕过.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 安装并显式启用

先安装或升级兼容的 AutoJs6, 再安装插件 APK. 在 AutoJs6 中进入 设置 > 关于应用和开发者, 长按应用图标打开开发者选项; 然后进入 DEX compiler > Raw JAR compiler provider, 选择下方 exact component 并确认. 仅安装插件不会启用路由, AutoJs6 也不会自动选择发现到的 provider.

#### 确认状态

回到开发者选项确认摘要明确显示 raw runtime.loadJar JAR 优先使用下方 exact component. 如果只显示 Built-in D8/dx 或找不到候选项, 请先核对宿主 build、两个包名、插件启用状态与签名. 该摘要只证明当前选择与发现资格, 不等于某一次编译已走远端, 更不等于 R1.3 已完成.

#### AutoJs6 示例

把包含 JVM `.class` 的可读 JAR 放到脚本目录的 `lib/example.jar`, 并将示例类名和方法替换为 JAR 中真实存在的 public API. 脚本通过既有 `runtime.loadJar()` 入口使用所选 provider; 插件不会增加新的 JavaScript 全局对象.

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

此示例只覆盖 raw JAR. `.aar`、已编译 `.dex`、兼容辅助路径和动态 `defineClass()` 始终保留在宿主内置路径. 不可信字节码在编译后仍不安全, 只加载你信任的 JAR.

#### 采集诊断

报告问题时请记录 AutoJs6 build/版本、插件版本、开发者选项中的完整 exact component 摘要、设备型号/API/ABI、输入 JAR 的字节数与 SHA-256、发生时间、完整脚本异常及复现步骤. 如使用 ADB, 对每条命令显式填写唯一获授权设备的 `<serial>`, 截取故障时间附近的 AndroidClassLoader/AndroidRuntime 日志, 并在分享前删去私有路径、脚本内容和其他敏感数据.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 禁用与紧急回滚

在开发者选项的 Raw JAR compiler provider 中选择 Built-in D8/dx 并确认, 然后停止并重新启动 AutoJs6. 这会关闭实验路由但保留已选组件记录, 便于以后重新选择. 紧急情况下应先禁用并重启宿主; 不需要卸载 AutoJs6、清除其数据或删除脚本. 已打开的进程级安全熔断会保守地保持到该 AutoJs6 进程结束.

#### 理解 fallback

路由关闭、provider 不可用或不兼容、绑定/远端失败、超时、输出无效或已验证产物加载失败时, 一次调用最多转入一次宿主内置 D8/dx; 已 dispatch 的 Binder 工作不会自动重试. 调用方取消或线程中断会直接传播且不会本地回退. AAR、loadDex 和 defineClass 本来就不经过插件. 因而脚本最终成功只能说明某条可用路径成功, 不能单独证明插件完成了编译.

#### 卸载与恢复

先选择 Built-in D8/dx, 确认摘要已关闭实验, 再停止 AutoJs6 并卸载插件. 卸载会永久删除插件自己的应用数据和私有临时工作区, 但宿主可继续使用内置编译器. 恢复时安装兼容且同签名的插件, 重新打开开发者选项并再次显式选择 exact component; 不要假定旧选择会自动恢复为启用状态.

#### 已知限制与验收边界

V1 仅处理有界 raw JVM JAR 到 DEX ZIP 的转换, 不提供 R8 shrinking/obfuscation、外部 classpath、自定义 desugared library、网络编译或确定性字节输出. BUSY 可触发宿主回退, 取消后 D8 CPU 工作可能在隔离进程中继续到清理完成. API 31 arm64 的 R1.2 证据不能替代 R1.1 production fault/rollback 门禁或 API 24/25/26/28/34/36 与 x86_64/arm64 的 R1.3 矩阵; 在这些项勾选前应把本指南视为受控预览.

******

### 开发路线图

******

R1.2 已达 4/4: 宿主 DEX 16 suites/149 tests 全通过, Android-test Kotlin 与 host/test APK assemble 成功, API 31 arm64 上 2 个 production concurrency、2 个真实 lifecycle 和 3 个真实 corpus 方法逐项通过. 并发探针统计 committed remote dispatch, 不直接统计 provider openSession; 独立重型 multi-dex 门禁生成 65,700 个方法并从主、次 DEX 加载类. 当前 host/test/plugin SHA-256 前缀为 181E38E8、70FAE1E8、5B6AC53B, signer 同为 31a681fc. 最终 host/test/plugin 卸载均成功, fake provider 保持 absent, 相关进程数为 0. R1.1 保持 0/7, R1.3 全未勾. R2 仅启动恢复切片: process-once strict-canonical janitor 通过插件 48/48 与 workspace recovery 6/6, 在首次 Binder 暴露前清除真实 force-stop 旧 UUID, 正常 D8 加载后 workspace 仍为空; R2 其余项继续未勾.

- [查看可勾选的 ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

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
