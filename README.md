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

- V1.0 接受一个 raw program JAR; V1.1 接受一个 program JAR 与至少一个有序的 compile-only classpath JAR. 两者均支持 DEBUG 或 RELEASE 模式, minApi 24 至 36 和 multi-dex 输出.
- 在编译前核验声明的大小和 SHA-256, ZIP framing, entry 名称, class magic, 重复项和解压边界.
- 使用设备 runtime boot classpath 及其指纹编译. V1.1 classpath 由宿主冻结并封装, 插件不接收调用方路径或任意 provider 文件系统 classpath.
- 仅封装连续的 `classes.dex`, `classes2.dex` 等 DEX 文件, 并返回实际 ZIP 大小和 SHA-256.
- Android API 26 及更高版本使用 D8Command, API 24 和 25 使用 D8 CLI fallback.

******

### 输入和输出格式

******

协议 V1.0 通过输入描述符接收一个 raw program JAR; V1.1 通过同一个有界输入描述符接收一个 program JAR 与至少一个有序的 compile-only classpath JAR. 两者都只产生以下 D8 输出:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
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

插件声明 D8 8.13.22, 协议范围 V1.0 至 V1.1, JAR 输入, DEX ZIP 输出, DEBUG 和 RELEASE 模式, minApi 24 至 36 及 multi-dex. Runtime library model 为设备 boot classpath V1.

build 5270 是 legacy V1.0 的最低宿主要求; `runtime.loadJarWithClasspath` 还要求包含 R3.3 的配对宿主构建, 本轮代表性验收使用 build 5274. 插件不含 native library, 因而通过一个纯 JVM universal APK 支持所有设备 ABI.

******

### 宿主集成状态

******

> `runtime.loadJar` 与显式 `runtime.loadJarWithClasspath` 路由仍默认关闭, 且要求显式选择同签名 exact component. R1 的 canonical 真实 provider 矩阵保持 7/7; R3 的 V1.1 有序编译期 classpath 已由一个获授权 API 34/x86_64 真实 provider 场景代表性闭环, 不是新设备矩阵. production Runtime single-flight 在认证并最终化 key 后使用有界持久语义 cache. 任一 waiter 中断都只分离该调用方且不作本地回退; 最后一个 waiter 离开时会通过 leader-owned one-shot handle 协作请求 producer 取消, 有其他 waiter 时不得取消. 安全熔断在当前进程生命周期内保持保守.

******

### 安装与使用指南

******

这是默认关闭的显式 opt-in 路径, 不是安装后自动生效的替代编译器. R1 验收包含 API 24/25/26/28/31/34/36 的真实 provider 执行; R3 只增加一条 API 34/x86_64 的 V1.1 代表性纵向验收, 不重跑或扩大该矩阵. 这些闭环不会自动启用路由或把插件提升为默认编译器.

#### 安装前提

只从可信且成对发布的来源取得 AutoJs6 与插件. AutoJs6 build 5270 或更高可使用 legacy V1.0; `runtime.loadJarWithClasspath` 需要包含 R3.3 的配对宿主构建, 本轮代表性验收使用 build 5274. 宿主与插件的完整当前签名证书集合必须相同; 自行构建时也必须保留下面的固定包名和服务组件. 升级前备份脚本与重要应用数据. 若 Android 报签名不匹配, 不要通过卸载宿主或清除数据来绕过.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 安装并显式启用

先安装或升级兼容的 AutoJs6, 再安装插件 APK. 在 AutoJs6 中进入 设置 > 关于应用和开发者, 长按应用图标打开开发者选项; 然后进入 DEX compiler > Raw JAR compiler provider, 选择下方 exact component 并确认. 仅安装插件不会启用路由, AutoJs6 也不会自动选择发现到的 provider.

#### 确认状态

回到开发者选项确认摘要明确显示 raw `runtime.loadJar` JAR 优先使用下方 exact component; 同一个选择也控制显式 `runtime.loadJarWithClasspath`. 如果只显示 Built-in D8/dx 或找不到候选项, 请先核对宿主 build、两个包名、插件启用状态与签名. 该摘要只证明当前选择与发现资格, 不等于某一次编译已走远端. 已有验收也不会取消每次请求的身份复核、握手、验证或回退规则.

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

上述示例覆盖 V1.0 raw JAR. 需要有序编译期 classpath 时可显式调用:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

该入口至少需要一个 classpath JAR, 保留声明顺序并把它纳入 cache identity. classpath 只供 D8 编译查找, 不进入输出也不自动装载; program 引用的运行时类型必须已由最终 program loader 的 parent 提供. 先用 `runtime.loadJar()` 加载依赖只会创建 sibling loader, 不能建立这种 parent 可见性. `.aar`、已编译 `.dex`、兼容辅助路径和动态 `defineClass()` 始终保留在宿主内置路径. 不可信字节码在编译后仍不安全, 只加载你信任的 JAR.

#### 采集诊断

报告问题时请记录 AutoJs6 build/版本、插件版本、开发者选项中的完整 exact component 摘要、设备型号/API/ABI、program 与每个有序 classpath JAR 的字节数和 SHA-256、发生时间、完整脚本异常及复现步骤. 如使用 ADB, 对每条命令显式填写唯一获授权设备的 `<serial>`, 截取故障时间附近的 AndroidClassLoader/AndroidRuntime 日志, 并在分享前删去私有路径、脚本内容和其他敏感数据.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 禁用与紧急回滚

在开发者选项的 Raw JAR compiler provider 中选择 Built-in D8/dx 并确认, 然后停止并重新启动 AutoJs6. 这会关闭实验路由但保留已选组件记录, 便于以后重新选择. 紧急情况下应先禁用并重启宿主; 不需要卸载 AutoJs6、清除其数据或删除脚本. 已打开的进程级安全熔断会保守地保持到该 AutoJs6 进程结束.

#### 理解 fallback

legacy `runtime.loadJar()` 固定使用 V1.0, 在允许回退的失败上仍至多转入一次宿主内置 D8/dx. 非空 classpath 的 `runtime.loadJarWithClasspath()` 请求 V1.1; 路由关闭、旧 provider、绑定/远端失败、超时、输出无效或 adoption 失败时, 宿主仅可用完全相同的冻结 program+ordered classpath 转入一次本地 D8, 不得忽略 classpath、静默降为 V1.0 或进入 dx. 已 dispatch 的 Binder 工作不会自动重试; 调用方取消或线程中断会直接传播且不回退. AAR、loadDex 和 defineClass 本来就不经过插件, 因而脚本最终成功不能单独证明插件完成了编译.

#### 卸载与恢复

先选择 Built-in D8/dx, 确认摘要已关闭实验, 再停止 AutoJs6 并卸载插件. 卸载会永久删除插件自己的应用数据和私有临时工作区, 但宿主可继续使用内置编译器. 恢复时安装兼容且同签名的插件, 重新打开开发者选项并再次显式选择 exact component; 不要假定旧选择会自动恢复为启用状态.

#### 已知限制与验收边界

V1 仅处理有界 JVM JAR 到 DEX ZIP 的转换. V1.1 的 bundled classpath 是 compile-only, 不是运行时依赖打包、combined loader 或任意外部 classpath; 也不提供 R8 shrinking/obfuscation、自定义 desugared library、Maven/Gradle 下载解析、网络编译或确定性字节输出. `DexCompilerMode.RELEASE` 只选择 D8 的 release compilation mode; 它不启用 R8, 也不承诺 shrinking、optimization、obfuscation 或 mapping. BUSY 可触发符合对应版本语义的宿主回退. 最后一个 waiter 离开会协作请求取消, 终止后禁止发布并最终清理; 若 D8 已进入不可中断调用, CPU 工作仍可能在隔离进程中继续到当前编译返回. 性能晋级、默认启用、全 API/ABI V1.1 矩阵及移除宿主编译器依赖不属于本轮闭环范围.

******

### 开发路线图

******

R1 与 R2 保持闭环. R3 已完成 V1.0/V1.1 并存 wire、provider canonical bundle、宿主同语义 D8-only fallback、多输入 cache/single-flight identity 和显式 Rhino 入口, 并在一个获授权 API 34/x86_64 目标上完成真实 provider classpath 编译、最终 DexClassLoader 执行和一次 V1.0 回归. 这是一条代表性纵向证据, 不是新的设备矩阵; 路由仍默认关闭, 调用方取消不回退, classpath 仍是 compile-only. 详细状态和可复核证据以 ROADMAP 为准.

- [查看可勾选的 ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### 安全性

******

插件不请求网络或存储权限. 编译服务受 `org.autojs.permission.PLUGIN` 保护, 并核验 AutoJs6 包名, 调用 UID 归属及双方签名. 输入输出描述符在异步处理前复制, 临时文件仅位于应用私有 cache 并在 worker 退出后清理.

******

### 运行限制

******

- 压缩 JAR 最大 64 MiB, 最多 20000 个 entry, 解压总量最大 256 MiB.
- V1.1 最多接受 32 个 classpath JAR, 单个压缩 classpath JAR 最大 64 MiB, classpath 压缩总量最大 128 MiB, 整个 canonical bundle 最大 256 MiB.
- class 数据总量最大 128 MiB, 单个 class 最大 8 MiB. Entry 和整体压缩比均受限制.
- DEX ZIP 最大 16 MiB, 最多 64 个连续编号的 DEX entry. 请求可声明更低的输出上限.
- 同一进程最多有一个活动编译会话. 忙碌请求会返回可重试的 BUSY 错误.
- 诊断数据最多 64 KiB, 错误文本和回调队列也有独立上限.

******

### 限制和注意事项

******

- 取消或关闭会立即阻止结果发布, 关闭描述符并中断 worker, 但 D8 的 CPU 工作无法可靠中断.
- 取消后的会话槽会一直保留到 D8 worker 实际退出并完成清理, 期间新请求仍会收到 BUSY.
- 插件不声明确定性. V1.1 只接受宿主冻结在 canonical bundle 中的 compile-only classpath, 不接收调用方路径、任意 provider 文件系统 classpath 或自定义 desugared library 配置.
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

编译器通过 Maven 使用 D8 8.13.22. 本地 AAR 只提供稳定协议边界, 生成的插件是无 native library 的 universal APK.

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
