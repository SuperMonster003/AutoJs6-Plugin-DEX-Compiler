<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>AutoJs6 独立 DEX 编译插件. 在隔离进程中使用较新的 D8 将脚本 JAR 编译为 DEX</p>

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

AutoJs6 的脚本可以通过 `runtime.loadJar()` 加载 JAR 并调用其中的 Java 类. 由于 Android 无法直接运行 JVM 字节码, 这些 JAR 必须先被编译为 DEX; 默认情况下, 这一步由 AutoJs6 内置的编译器完成.

本插件提供另一种选择: 它是一个独立安装的应用, 在自己的隔离进程中用较新版本的 Google D8 编译器完成这步编译. AutoJs6 把 JAR 交给插件编译, 拿回 DEX 结果后自行验证, 缓存并加载; 插件出现任何问题时, AutoJs6 会自动退回内置编译器, 脚本通常不受影响.

适合安装本插件的场景: 希望使用比 AutoJs6 内置版本更新的 D8; 希望编译过程运行在与 AutoJs6 隔离的进程中; 或希望在不升级 AutoJs6 的情况下单独升级编译器.

******

### 工作原理

******

启用插件后, 一次 `runtime.loadJar()` 调用大致经历以下步骤:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

插件只负责第 3 和第 4 步, 即 "编译" 本身; 输入的固定, 结果的验证, 缓存与最终加载始终由 AutoJs6 完成. 双方通过 Binder 只传递文件描述符, 插件不会读取脚本目录, 也不知道文件的原始路径. 编译结果按输入内容与编译参数缓存, 相同输入的重复加载会直接命中缓存, 无需再次编译.

******

### 功能特性

******

- 编译由 D8 8.13.22 完成, 插件可独立于 AutoJs6 更新编译器版本.
- 编译运行在插件自己的独立进程与私有工作区中, 崩溃或失败不影响 AutoJs6 主进程.
- 双重校验: 插件在编译前核对 JAR 的大小, SHA-256, ZIP 结构与 class 内容; AutoJs6 在编译后独立复验 DEX 输出.
- 支持 DEBUG 与 RELEASE 编译模式, multi-dex 输出, 以及 minApi 24 至 36 的编译参数.
- 支持 Android 7.0 (API 24) 及以上的所有设备; API 26+ 使用 D8Command, API 24/25 自动切换到 D8 CLI 兼容路径.
- V1.1 协议支持有序的编译期 classpath (`runtime.loadJarWithClasspath()`), 用于编译引用了外部 API 的 JAR.
- 任何失败都会让 AutoJs6 至多自动回退一次到内置编译器, 不会让脚本卡死在插件上.

******

### 安装与使用

******

启用插件共三步: 安装兼容的 AutoJs6, 安装本插件 APK, 然后在 AutoJs6 开发者选项中手动选择本插件. 有两点需要提前了解:

- 插件默认不生效. 仅安装不会改变 AutoJs6 的任何行为, 必须按下文手动启用.
- 随时可以撤销. 在开发者选项中切回 Built-in D8/dx 即可恢复原状, 无需卸载任何应用.

#### 安装前提

- AutoJs6 build 5270 或更高 (对应 `runtime.loadJar()`); `runtime.loadJarWithClasspath()` 需要更新的配对宿主构建 (验证时使用 build 5274).
- 宿主与插件必须来自同一可信来源且签名一致. 签名不一致时插件无法被选中; 请改用成对发布的安装包或成对自行构建, 不要用卸载宿主或清除数据的方式绕过.
- 自行构建时保持下方固定的包名与服务组件不变.
- 升级前建议备份脚本与重要数据.

相关标识如下:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 安装并启用

1. 安装或升级到兼容版本的 AutoJs6.
2. 安装本插件 APK.
3. 打开 AutoJs6, 进入 设置 > 关于应用和开发者, 长按应用图标进入开发者选项.
4. 进入 DEX compiler > Raw JAR compiler provider.
5. 选中本插件的服务组件 (即上方 exact component) 并确认.

再次强调: 仅安装插件不会自动启用, AutoJs6 也不会自动选择它发现的任何 provider; 第 3 至 5 步是必需的.

#### 确认已生效

回到开发者选项页面, 当摘要显示已选择本插件的服务组件时, 表示启用成功: 此后脚本中 `runtime.loadJar()` 与 `runtime.loadJarWithClasspath()` 的编译会优先交给插件处理.

如果列表中找不到本插件, 或摘要仍显示 Built-in D8/dx, 请依次检查: AutoJs6 build 是否不低于 5270; 宿主与插件的包名是否与上方一致; 插件应用是否被系统禁用; 两者签名是否一致.

注意: 该摘要表示的是 "当前选择了谁", 而非 "某次编译实际由谁完成"; 单次编译仍可能因缓存命中或失败回退而未经过插件 (见下文).

#### 脚本示例

把包含 JVM `.class` 文件的 JAR 放到脚本目录的 `lib/example.jar`, 然后在脚本中正常调用 `runtime.loadJar()` 即可; 插件不添加任何新的 JavaScript 全局对象, 脚本写法与使用内置编译器时完全相同. 示例中的类名和方法请替换为你的 JAR 中真实存在的 public API.

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

若 JAR 编译时引用了运行环境中已存在, 但本身不在该 JAR 内的类 (例如某些 API stub), 可以使用显式的编译期 classpath 入口:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

关于 classpath 的三个要点:

- classpath JAR 只在编译期用于解析引用, 不会打包进输出, 也不会被自动加载.
- 若 program 在运行时确实要用到这些类, 它们必须已存在于最终类加载器的 parent 链中 (如 Android 系统类或 AutoJs6 自带类). 先用 `runtime.loadJar()` 加载依赖 JAR 无法满足这一点, 那只会创建一个平级的加载器.
- classpath 的声明顺序有意义并参与缓存标识; 该入口至少需要传入一个 classpath JAR.

另外, `.aar` 文件, 已编译的 `.dex`, 以及 `defineClass()` 等动态入口始终由 AutoJs6 内置路径处理, 与本插件无关. 最后请牢记: 编译不等于安全审查, 只加载你信任的 JAR.

#### 编译失败时会发生什么

启用插件后, AutoJs6 依然把 "脚本能跑起来" 放在第一位:

- `runtime.loadJar()`: 插件不可用, 编译失败, 超时或输出未通过验证时, AutoJs6 会用同一份 JAR 自动改用内置 D8/dx 编译, 每次请求至多回退一次.
- `runtime.loadJarWithClasspath()`: 回退同样至多一次, 且必须带着完全相同的 program 与 classpath 交给本地 D8 重新编译; 不会丢弃 classpath, 也不会静默降级.
- 你主动取消 (例如停止脚本) 不属于失败, 不会触发回退, 而是直接结束本次加载.
- 插件返回 BUSY (同一时刻只允许一个编译会话) 时, AutoJs6 按上述规则处理, 稍后重试脚本即可.

因此脚本最终成功运行并不能证明那次编译经过了插件; 需要确认时请参考下文的排查方法.

#### 排查问题与反馈

怀疑插件工作不正常时, 可先切回 Built-in D8/dx 对比行为是否变化. 反馈问题时请尽量附上以下信息:

- AutoJs6 build/版本, 插件版本, 以及开发者选项摘要中的完整组件名.
- 设备型号, Android 版本 (API) 与 CPU 架构 (ABI).
- 触发问题的 JAR (或其字节数与 SHA-256), 完整脚本异常信息与复现步骤.

如果会使用 ADB, 以下命令可采集相关日志 (`<serial>` 替换为你的设备序列号; 分享前请删去日志中的私有路径与敏感内容):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 关闭, 回滚与卸载

- 临时关闭: 在开发者选项的 Raw JAR compiler provider 中选择 Built-in D8/dx 并确认, 然后完全退出并重启 AutoJs6. 组件选择记录会被保留, 之后可以随时重新启用.
- 遇到紧急问题: 按上述方式关闭并重启宿主即可, 不需要卸载 AutoJs6, 清除其数据或删除脚本.
- 卸载插件: 先切回 Built-in D8/dx, 再停止 AutoJs6 并卸载插件 APK. 卸载会清除插件自己的全部数据与临时文件; AutoJs6 继续使用内置编译器, 不受影响.
- 重新安装后需要重新手动启用, 旧的选择不会自动恢复.

******

### 常见问题

******

**问: 安装插件后脚本没有任何变化, 是坏了吗?**

答: 不是. 插件默认关闭, 需要在开发者选项中手动启用 (见上文); 且它只影响 `runtime.loadJar()` 与 `runtime.loadJarWithClasspath()` 的编译环节, 不改变脚本的其他行为.

**问: 如何确认某次编译真的由插件完成?**

答: 开发者选项摘要只表示 "已选择插件". 由于失败会自动回退且结果会被缓存, 脚本成功不能反推编译经过插件; 可按 "排查问题与反馈" 一节采集日志确认.

**问: 这个插件能让脚本跑得更快吗?**

答: 它的目标是更新的编译器, 更严格的输入校验与进程隔离, 而不是性能. 编译耗时与内置编译器大体相当, 且已编译结果会被 AutoJs6 缓存.

**问: 插件支持 R8 压缩/混淆吗? RELEASE 模式是不是 R8?**

答: 不支持, 也不是. 本插件只做 D8 编译; `RELEASE` 只是 D8 的 release 编译模式, 不包含 shrinking, obfuscation 或 mapping. R8 能力属于另一个独立的 provider 插件, 不在本插件范围内.

**问: 为什么要求宿主与插件签名一致?**

答: 这是双向的安全校验: 防止其他应用冒充 AutoJs6 调用插件, 也防止被篡改的插件冒充编译服务. 签名不一致时请更换成对发布的安装包, 不要用卸载或清除数据绕过.

**问: 插件会联网或读取我的文件吗?**

答: 不会. 插件没有网络与存储权限, 只能通过 AutoJs6 递来的文件描述符读取待编译内容, 临时文件全部位于自己的私有目录.

******

### 能力边界

******

为避免误解, 以下事项明确不属于本插件的功能范围:

- 不做 R8 shrinking, optimization, obfuscation, 也不生成 mapping 文件; `RELEASE` 仅代表 D8 的 release 编译模式.
- 不下载或解析依赖 (没有 Maven/Gradle 集成), 不进行网络编译.
- 不处理 `.aar`, 已编译的 `.dex` 与 `defineClass()` 动态字节码, 它们始终走 AutoJs6 内置路径.
- V1.1 classpath 仅用于编译, 不打包运行时依赖, 也不建立组合类加载器.
- 不承诺字节级确定性输出: 相同输入在不同编译器版本下可能产生不同但等价的 DEX.
- 不替代 AutoJs6 的输出验证: 宿主始终对 DEX 结果做独立复验.
- 不会自动成为默认编译器: 启用与否始终由用户显式控制.

******

### 技术参考

******

以下内容面向需要精确边界的开发者与集成方; 仅使用插件时通常无需阅读.

#### 输入与输出

协议 V1.0 通过输入描述符接收一个 raw program JAR; V1.1 在同一个有界输入包中接收一个 program JAR 与至少一个有序的编译期 classpath JAR. 两者产生相同形式的输出:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### 插件发现标识

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

插件声明 D8 8.13.22, 协议范围 V1.0 至 V1.1, JAR 输入, DEX ZIP 输出, DEBUG 与 RELEASE 模式, minApi 24 至 36 及 multi-dex; runtime library model 为设备 boot classpath V1.

build 5270 是 V1.0 的最低宿主要求; `runtime.loadJarWithClasspath()` 需要包含 V1.1 支持的配对宿主构建 (代表性验证使用 build 5274). 插件不含 native library, 以一个纯 JVM universal APK 覆盖所有设备 ABI.

#### 安全模型

插件不申请网络与存储权限. 编译服务受 `org.autojs.permission.PLUGIN` 权限保护, 每次调用都会核验 AutoJs6 的包名, 调用方 UID 归属与双方签名. 输入输出均通过文件描述符传递并在异步处理前复制, 临时文件仅位于插件私有 cache 且会在编译结束后清理.

#### 资源上限

为防御恶意或异常输入, 插件对各环节设置了硬性上限, 超限请求会被直接拒绝:

- 输入 JAR: 压缩后最大 64 MiB, 最多 20000 个 entry, 解压总量最大 256 MiB.
- V1.1 classpath: 最多 32 个 JAR, 单个压缩后最大 64 MiB, classpath 压缩总量最大 128 MiB, 整个输入包最大 256 MiB.
- class 数据: 总量最大 128 MiB, 单个 class 最大 8 MiB; entry 与整体压缩比另有限制.
- 输出 DEX ZIP: 最大 16 MiB, 最多 64 个连续编号的 DEX entry; 请求可声明更低的上限.
- 并发: 同一进程同时只处理一个编译会话, 其余请求收到可重试的 BUSY 错误.
- 诊断数据最多 64 KiB, 错误文本与回调队列亦有独立上限.

#### 注意事项

- 取消或关闭会立即阻止结果发布并中断 worker, 但 D8 内部的 CPU 计算无法保证立刻停止, 可能在隔离进程中继续到本次编译返回.
- 取消后的会话槽会保留到 worker 实际退出并完成清理, 期间新请求仍会收到 BUSY.
- 插件不声明确定性输出; 缓存标识包含编译器版本与运行时指纹, 版本变化不会误用旧结果.
- V1.1 只接受宿主冻结打包的编译期 classpath, 不接收调用方文件路径或自定义 desugared library 配置.
- 设备 runtime boot classpath 因系统而异, 请求必须与 provider 报告的 runtime 指纹一致.

******

### 开发路线图

******

开发按阶段推进, R0 至 R5 均已在当前授权边界内完成并留有可复核证据. R5.2 的有界并行候选仍为 `NOT_PROMOTED`, 因为纠正后的三个进程冷启动缓存命中 added P95 时延格均超过 100 ms. R5.3 冻结了携带 D8 8.13.22 的 v1.1.0, 并在 API 24/x86、API 34/x86_64 和 API 35/arm64 的代表性真实 provider classpath 格通过; 双净目录调查中 54 个产出格的跨目录输出摘要差异为 0, 同时保持 `determinismClaim=NOT_CLAIMED`. R5.4 已按 owner 明确决策收口: 独立 R8 provider 的现有 prerelease 已转为 non-prerelease Release, 但仓库继续保持 Private; 仓库公开化、配对 AutoJs6 build 5276 的公开发布与官方插件索引手动登记均未执行, 并整体移交未来独立 R8 G9 Public Gate. 这不是公开发布, 也不改变插件默认关闭状态. 各条目的完成定义与证据见:

- [查看可勾选的 ROADMAP.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### 版本历史

******

# v1.1.2

###### 2026/09/15

* `修复` 通过 AGP 解析 D8 测试矩阵的 android.jar, 并延迟到任务执行时读取 boot classpath, 修复提前创建 Test 任务时的构建失败
* `优化` 将 compileSdk 与 targetSdk 提升到 37 (Android 17), 插件行为不受新目标版本影响

# v1.1.1

###### 2026/09/13

* `修复` 插件版本日期固定使用英文, 不随构建机器的语言变化
* `优化` 统一多语言资源, 明确插件激活契约并校验发布产物

# v1.1.0

###### 2026/09/11

* `提示` `runtime.loadJarWithClasspath()` 需要配对的 AutoJs6 build 5274 或更高版本; 普通 `runtime.loadJar()` 继续兼容 build 5270 或更高版本
* `新增` 支持 V1.1 有序编译期 classpath: program JAR 可引用外部 API JAR, classpath 只参与编译, 不会打包进 DEX 或自动加载
* `修复` 兼容长度声明一致且在文件边界精确结束的标准 ZIP/JAR archive comment, 同时继续拒绝歧义 EOCD, 长度不一致和尾随数据
* `修复` 在 Release 压缩构建中完整保留嵌入式 D8 引擎及其服务提供者, 使生产 APK 可以正常编译 JAR
* `优化` 提供有界且脱敏的 D8 info/warning/error 诊断, 包含可用的来源, archive entry 与位置元数据, 便于定位插件编译失败
* `优化` 将 D8 内部并行编译限制为两个工作线程, 降低大型 JAR 冷编译的峰值内存, 不改变输出与缓存语义
* `优化` 构建阶段阻止意外引入原生依赖, 并输出 JSON 校验报告
* `依赖` 升级 Google R8 库至 8.13.22 (提供 D8 编译器)

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

编译器通过 Maven 引入 D8 8.13.22. 本地 AAR 只提供稳定的协议边界, 构建产物是不含 native library 的 universal APK.

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

`.python/generate_markdown.py` 从 JSON 源生成全部 10 种语言的 README 与应用内更新日志; 修改文档请编辑 JSON 源而非生成的 Markdown. Android 界面字符串由各自的资源目录管理.

******

### 链接

******

- AutoJs6 文档: https://docs.autojs6.com
- R8 项目: https://r8.googlesource.com/r8


[16 KB page alignment and build verification](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/docs/16kb.md)
