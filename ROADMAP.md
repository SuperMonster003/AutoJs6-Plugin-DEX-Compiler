# DEX Compiler Roadmap

更新日期: 2026-08-27

本路线图把后续工作拆成可独立验收的 R0-R5。每个复选框只表示对应条目已经有可复核证据，不能用较低层级的测试替代较高层级的验收。例如，JVM 单元测试通过不等于跨 APK Binder 或真实设备加载已经通过。

## 状态与证据规则

- `[x]` 表示条目已经完成，并且本仓库或对应宿主仓库中存在可复核证据。
- `[ ]` 表示尚未完成，或虽有实验结果但尚未达到该条目的完成定义。
- 每个阶段只有在其“退出条件”全部勾选后才算完成。
- 诊断 smoke、fake provider 测试和替代设备结果只能作为补充证据，不能改写为 canonical acceptance。
- 失败的验收记录需要保留，并明确环境、命令、失败阶段和后续处置。
- R0 是纯本地阶段，不运行 `adb`、`connected*`、安装或任何设备任务。R1 设备矩阵只能使用用户明确允许的设备。

## 总览

| 阶段 | 状态 | 核心结果 | 主要仓库 |
|---|---|---|---|
| R0 | 已完成 | 低内存 JAR 验证、对抗性测试语料和可重复本地门禁 | 本插件 |
| R1 | 已完成 | AutoJs6 显式 opt-in 接入、生产加载链路与真实 provider 7-cell 设备矩阵 | AutoJs6 + 本插件 |
| R2 | 已完成（交付 4/4，退出 1/1） | 有界故障摘要、协作取消、fail-closed 终态与启动恢复 | AutoJs6 + 本插件 |
| R3 | 已完成（交付 4/4，退出 1/1） | V1.1 有序编译期 classpath、同语义回退与多输入缓存 | 协议 + AutoJs6 + 本插件 |
| R4 | 已完成（R4.1 4/4；R4.2 5/5；R4.3 2/2；退出 2/2） | D8 已完成默认晋升、旧 pin 回滚与再晋升；独立 R8 provider 已完成宿主显式选择、跨 APK Binder/PFD、设备/ART/JNI/Retrace、append-only 本地发布及 Private prerelease；源码编译与 AAR/APK 职责继续隔离 | 本插件 + AutoJs6 + 独立 R8 provider |
| R5 | 已完成（R5.0 6/6、R5.1 4/4、R5.2 3/3、R5.3 3/3；R5.4 公开范围已明确移交 R8 G9；退出 2/2） | 用户文档、独立走查、诊断闭环、V1.1 三格矩阵、v1.1.0 发布与双净目录调查均已完成；R5.2 候选未晋级且默认启用前置仍为 3/7。独立 R8 provider 已从 Private prerelease 转为仍在 Private 仓库内的正式 Release；仓库公开化、配对宿主公开发布与索引登记未执行，移交未来独立 R8 G9 Public Gate | 本插件 + AutoJs6 + 独立 R8 provider |

依赖顺序:

```text
R0 ──> R1 ──> R2 ──> R3
                    └──> R4 ──> R5
```

R4 的设计工作可以提前开展，但不得在 R0-R3 的接口中偷偷引入 shrinking、obfuscation 或源码编译语义。R5.0 的文档条目是纯本地工作，不依赖设备；R5.1-R5.3 中涉及设备的条目沿用 R1 的授权设备规则。R5 已按当前授权边界关闭，但这不代表性能候选晋级、插件改为默认启用，或独立 R8 provider 已公开。

## R0: 低内存验证与本地质量门禁

目标: 在不改变 DEX Compiler 协议 V1 和既有安全策略的前提下，消除生产验证路径对整个压缩 JAR 的内存副本，并把 ZIP/JAR 边界变成可持续回归的本地验收面。

### R0.0 范围冻结

- [x] 确认 R0 只改本插件，不接入 AutoJs6 的 `AndroidClassLoader`。
- [x] 确认 R0 不改变协议 V1、provider identity、输入输出格式、资源上限或签名鉴权。
- [x] 确认 R0 不执行 ADB、安装、`connected*` 或其他设备任务。
- [x] 建立本路线图，并把 README 指向本文件。

### R0.1 低内存 JAR 验证

- [x] 生产代码不再通过 `File.readBytes()` 或等价方式把完整压缩 JAR 复制到堆内存。
- [x] ZIP framing 检查改为基于文件的有界随机读取；偏移和长度计算继续使用溢出安全的 `Long` 运算。
- [x] EOCD、中央目录、本地文件头、extra field 和 data descriptor 的检查保持严格；R0 当时不放宽 ZIP64、多磁盘、加密、archive comment、前置/尾随数据或未知压缩方法限制。R5 的受控兼容后续仅接受长度声明一致、在文件边界精确结束且 EOCD 唯一无歧义的标准 archive comment。
- [x] entry 内容仍以固定大小缓冲区流式解压，并继续执行单项、累计、class 总量、class magic 和压缩比限制。
- [x] 保留输入复制阶段的大小与 SHA-256 同步核验，失败时删除未完成的私有临时文件。
- [x] 正常 JAR 的 `ValidatedJar` 统计结果与改造前保持一致。
- [x] 对恶意长度、截断文件和不可读文件只返回有界、类型明确的失败，不泄漏运行时异常或产生无限循环。

### R0.2 对抗性与边界测试

- [x] 正向语料覆盖 STORED、DEFLATED、带/不带签名的 data descriptor、目录 entry、多个 class 和非 class 资源。
- [x] 覆盖恰好等于及超过压缩大小、entry 数、解压总量、单 class、class 总量和压缩比上限的边界。
- [x] 覆盖 EOCD 缺失、前置/尾随字节、中央目录截断、entry 数或目录大小不一致；R0 当时把任意 archive comment 作为拒绝语料，R5 后续改为接受精确声明的标准注释，并继续拒绝长度不一致、歧义 EOCD 与注释后的尾随字节。
- [x] 覆盖本地头与中央目录之间的名称、flags、method、CRC、压缩大小和解压大小不一致。
- [x] 覆盖 ZIP64 sentinel/extra field、多磁盘、加密、不支持的压缩方法、记录间空洞、重叠和乱序 offset。
- [x] 覆盖空名称、绝对路径、`..`、反斜杠、冒号、NUL、非 NFC、重复名称和非规范目录结尾。
- [x] 覆盖无 `.class`、伪 `.CLASS`、class magic 错误、目录携带数据和压缩炸弹。
- [x] 增加固定 seed 的 mutation/fuzz 回归；任一变体都必须在限定时间和内存内接受或返回协议化失败，不得 crash、hang 或 OOM。
- [x] 至少使用一个接近输入上限的大型稀疏/生成语料证明验证路径不创建与整个 JAR 等大的额外堆数组。

R0.2 的代表性回归切片:

- [x] 接受 STORED JAR，以及带签名 data descriptor 的 DEFLATED JAR，并核对 `ValidatedJar` 统计。
- [x] 拒绝本地文件头、中央目录和 EOCD 的固定截断变体。
- [x] R0 当时拒绝 archive comment、前置数据和尾随数据；R5 后续只把前置/尾随 envelope 及畸形或歧义 comment 保持为拒绝项，精确标准 comment 改为正向兼容语料。
- [x] 拒绝重复 entry、错误 class magic，以及 7 类危险或非 NFC 名称。
- [x] 拒绝未知压缩方法、ZIP64 sentinel、畸形 extra field 和错误 data descriptor。
- [x] 覆盖空输入与注入的复制异常，并核对未完成目标文件的清理行为。

### R0.3 可重复本地门禁

- [x] Markdown 生成器运行成功，并且第二次运行不产生差异。
- [x] `:app:testDebugUnitTest` 全部通过，测试报告保留准确用例数。
- [x] `:app:lintDebug` 完成且错误数为 0；warning 与 error 分开报告。
- [x] `:app:assembleDebug` 成功，证明 R0 改造未破坏 Android 构建。
- [x] 核对 `git diff --check` 无空白错误，工作树只包含本阶段预期文件。
- [x] 验收记录列出 JDK、Gradle/AGP、操作系统、精确命令、退出码和产物/报告路径。

建议的本地命令:

```powershell
python .\.python\generate_markdown.py
git diff --check
.\gradlew.bat :app:testDebugUnitTest :app:lintDebug :app:assembleDebug --console=plain
```

生成一致性应在生成产物已经提交后单独验证:

```powershell
python .\.python\generate_markdown.py
git diff --exit-code -- README.md .readme app/src/main/assets/doc
```

#### R0 退出条件

- [x] R0.1、R0.2、R0.3 全部完成。
- [x] 代码审查确认没有放宽既有 ZIP/JAR 安全不变量。
- [x] 本地门禁通过且没有把 JVM 结果描述成 Android/设备验收。
- [x] R0 状态由“进行中”更新为“已完成”，并记录最终证据。

### R0 本轮证据（2026-08-09，2026-08-10 强制门禁复核）

- 环境: Windows 11 10.0 amd64；Oracle JDK 21.0.1；Gradle 9.5.0；Android Gradle Plugin 9.2.1；Kotlin plugin 2.3.20。
- 文档: `python .\.python\generate_markdown.py` 连续运行两次，生成文件的 SHA-256 清单一致；10 个 locale JSON 均可解析。
- 本地门禁: 排队取得构建空窗后执行 `.\gradlew.bat :app:testDebugUnitTest --rerun-tasks -Pr0TestMaxHeap=60m`，`BUILD SUCCESSFUL`，耗时 1m01s；同轮此前的 `:app:lintDebug`、`:app:assembleDebug` 与 `:app:assembleRelease` 也均成功。
- 单元测试: 强制重跑结果为 10 个 suite、43 个 test，failure/error/skipped 均为 0；全量测试在 60 MiB 受限堆下通过，报告位于 `app/build/reports/tests/testDebugUnitTest/`。
- 大型语料: source 66,595,045 bytes，provider 输入上限 67,108,864 bytes，测试 JVM 最大堆 62,914,560 bytes；最大堆严格小于输入文件，验证成功且输入/输出摘要一致。
- Mutation: 固定 seed `0x5eed_c0de`，共 256 个 metadata mutation，在 10 秒测试时限内全部得到有界、协议化拒绝。
- Lint: error 0、warning 27；报告位于 `app/build/reports/lint-results-debug.html`。
- 产物: Debug 与 Release APK 均成功生成于 `app/build/outputs/apk/`；本轮没有签名发布、版本号变更或 commit。
- 边界: R0 阶段的本地门禁当时未运行 ADB、安装、`connected*` 或真实设备测试；后续 R1 的 API 31 真实插件定向方法另行记录，不能倒推为 R0 Binder 或设备验收证据。

### R0 archive comment 策略的 R5 兼容性后续（2026-08-26）

- R0 的“拒绝全部 archive comment”是当时的历史安全快照，不改写为当时已经兼容。R5 根据独立用户的真实 `java-websocket.jar` 样例，在不改变协议、预算、身份或发布 ownership 的前提下实施受控放宽。
- 当前 framing 只在文件末尾最多 `22 + 65,535` bytes 的有界窗口内反向查找 EOCD；仅当恰好一个自洽 EOCD 的 16-bit comment length 精确落到 EOF 时接受。ZIP64、多磁盘、加密、前置数据、注释后尾随数据、长度不一致及 comment 内伪造出的第二个自洽 EOCD 仍 fail-closed。
- 正向测试覆盖真实样例同形的 5-byte binary comment 与 65,535-byte 最大标准 comment；反向测试覆盖少报/多报长度、额外尾随字节和 comment 内伪 EOCD。该兼容面属于 R5 用户样例闭环，不倒改 R0 当轮“纯本地、无设备”的历史证据边界。

## R1: 宿主显式接入与真实 provider 验收

目标: 让 AutoJs6 用户可以显式选择本插件承担 JAR 到 DEX 的编译，同时保持默认行为、回退路径和发布安全边界可控。

### R1.0 接入决策

- [x] 在 AutoJs6 中提供默认关闭的显式设置；只接受用户选择并持久化的 exact component，展示关闭/已选择状态；R1.0 本身不接入 `runtime.loadJar()`。
- [x] 明确定义 provider 不存在、身份漂移、不兼容、BUSY、超时、远端失败、Binder death、回调/传输违规及输出拒绝时的单次本地回退；用户取消不切换编译器，失败不得发布插件半成品。
- [x] 明确 cache 和发布事务由宿主持有；宿主在握手后才协商协议并用当次 capability/runtime library fingerprint 最终化请求，同时执行最小宿主构建号、exact component、UID、完整 signer 集及同签名限制。
- [x] 提供无需卸载插件的关闭路径；关闭显式 opt-in 会阻止后续实验链路发现或绑定 provider，已持久化的 provider 选择不会自行重新启用。

R1.0 本轮实现边界:

- 设置保持默认关闭，不进行自动 provider 选择；只有显式保存的 exact component 可以进入候选检查。
- 设置摘要可观察关闭状态或保留的 exact component；发现成功时，选择器只列出当前通过本地包策略且与宿主同签名的唯一 component。
- R1.0 只建立控制面；其完成证据不包含 `runtime.loadJar()` / `AndroidClassLoader` 生产接线。该接线现由 R1.1 单独部署和验收。
- 宿主仍拥有输入快照、输出事务、验证后 cache 发布和回滚；provider 不获得宿主文件路径，也不能直接发布可加载产物。
- “官方”身份不能替代 provider 侧的同签名鉴权；正式验收仍须核对实际宿主 APK 与插件 APK 的 signer。

### R1.1 生产加载链路

宿主工作树已经完成 R1.1 production wiring。API 34 上 8/8 production-routing instrumentation、宿主 DEX 16 suites/149 tests、wire 4 suites/24 tests、fake-provider 5 suites/25 tests、既有 API 31 arm64 真实 provider lifecycle/concurrency/corpus，以及下述 canonical 7-cell 真实 provider Gate 共同关闭七项生产链路门禁。fake provider 与 JVM 结果只承担各自层级的故障注入和回归覆盖；R1.1 的端到端结论由真实 provider、真实 Binder/PFD、宿主验证/发布和 `DexClassLoader` 执行证据支撑。

R1.1 最初落地时的验证后发布只作为一次性 classloader handoff。该描述是历史边界，不再代表当前工作树；R1.2 已将其升级为有界的持久语义 cache，并由当前主源码门禁、production-routing instrumentation 与 canonical 设备矩阵复核。

- [x] 已验证: 宿主固定 raw JAR 输入快照，先计算大小和 SHA-256 再打开 session；若远端失败需要本地回退，只能复用同一份已保留快照。
- [x] 已验证: 只通过用户显式选择且与宿主完整 signer 集一致的 exact component 建立 Binder 会话；跨进程只传文件描述符，不向插件暴露路径。
- [x] 已验证: 固定 provider 身份并完成 Binder 握手后才最终化协议版本和 runtime library fingerprint；capability 与 ceiling 只用于验证或拒绝，不重写请求。
- [x] 已验证: 宿主用完整 `DexIndexedZipValidator` 独立复验输出大小、双重摘要、DEX header、命名连续性和条目边界。
- [x] 已验证: 验证产物仅能经宿主持有的复制、复核与原子发布进入 cache；失败、取消、超时、Binder death 或进程死亡使事务失效，不留下可加载半成品。
- [x] 已验证: 只有 raw `runtime.loadJar()` JAR 可把宿主已验证的 DEX ZIP 交给 `AndroidClassLoader`；AAR、`loadDex()`、`defineClass()` 与兼容辅助路径继续使用内置实现。
- [x] 已验证: 实验默认关闭；provider 未启用、不可用、远端失败、输出拒绝或 verified ZIP 接管失败时至多执行一次内置 D8/dx 回退，用户取消作为中断传播且不切换编译器。

### R1.2 自动化测试

R1.2 的四项精确定义均已有可复核的 JVM、编译与 API 31 arm64 真实插件证据，现为 4/4；该结果只关闭自动化测试阶段，不提前关闭 R1.1 或 R1.3:

- 宿主持久语义 cache 使用 generation artifact 与带校验和的 manifest；严格执行文件与目录 fsync 及原子 manifest commit，并提供启动恢复、LRU、单项 16 MiB、总量 128 MiB、最多 32 项和损坏 generation 精确淘汰。
- cache lookup 仅在同签名 exact component 完成认证握手且最终化 semantic key 后进行，并位于输入/输出 FD claim 与 `openSession` 之前；命中仍重跑当前 `DexIndexedZipValidator`，不会继承历史验证结论。
- lookup 先打开 descriptor，再对同一 inode 复验大小及 SHA-256；成功 classloader 接管保留 cache，非中断接管失败只淘汰当次 exact generation。
- production Runtime 已在认证握手并最终化 semantic attempt key 后接入进程级 single-flight：相同 key 共享一个 producer，成功结果为每个调用方取得独立 capability。R1 验收时任一 waiter 中断只分离该调用方且不触发本地回退；R2 已进一步补齐最后 waiter 离开时对 producer 的协作取消，有其他 waiter 时 producer 继续。
- 针对不安全 executor 拒绝或疑似 Binder 阻塞设置的熔断保持保守：一旦触发，在当前宿主进程生命周期内持续打开且不自动探测恢复；它不会被表述为已经强制终止远端或阻塞中的 Binder 工作。
- Android instrumentation 新增并逐项执行：2 个 production concurrency 方法、2 个真实插件 lifecycle 方法和 3 个真实 D8 corpus 方法。并发断言统计的是宿主越过提交点的 committed remote dispatch，而不是直接统计 provider `openSession` 调用；重型 multi-dex 语料运行时生成 7,300 个 class、合计 65,700 个方法，并作为独立长时门禁执行。

- [x] 已验证: 宿主单元测试覆盖 opt-in 默认值、provider 选择、能力不兼容、摘要不匹配、无效输出及回退；本轮 DEX 定向门禁 16 suites/149 tests，failure/error/skipped 均为 0。
- [x] 已验证: Binder 集成测试覆盖真实插件 APK、文件描述符 ownership、回调顺序、BUSY 和 Binder death；fake provider 仅作辅助测试。
- [x] 已验证: cache 测试覆盖 key、命中、并发请求合并、原子发布、损坏缓存淘汰和失败后重试。
- [x] 已验证: Java/Kotlin、single-dex/multi-dex、缺失依赖和重复加载用例最终由真实 `DexClassLoader` 执行验证。

### R1.3 真实设备矩阵

Canonical campaign `f3c2b1af-be93-41e7-b541-f167f90e5cc1` 的 Gate 为 7/7 PASS。API 24/25 使用 D8 CLI fallback；API 26/28/34/36 使用 `D8Command`，均为 x86_64 模拟器；API 31 使用获授权的 `QV710AF65F` arm64-v8a 真机，并在不改变其 user 0/user 10 拓扑及邻近包的前提下完成多用户 fail-closed 清理。

- [x] API 24 和 25: 验证 D8 CLI fallback 与真实类加载。
- [x] API 26: 验证 `D8Command` 分界版本。
- [x] API 28: 验证中间版本兼容性。
- [x] API 34 和 36: 验证现代 Android 行为与目标 SDK 边界。
- [x] 至少覆盖一个 arm64 真机和一个 x86_64 模拟器；具体设备已经用户许可。
- [x] 每个 canonical matrix 单元记录宿主/插件版本、commit、API/ABI、输入摘要、provider identity、输出摘要和执行结果。
- [x] 失败矩阵证据保留原样；替代设备或 smoke 通过没有覆盖原失败记录。

#### R1 退出条件

- [x] 显式 opt-in、回退和回滚路径均可用，默认用户行为未改变。
- [x] 真实插件设备矩阵全部通过，且未用 fake provider 冒充端到端验收。
- [x] 用户文档提供安装、启用、诊断、禁用和回退步骤。

### R1 本轮阶段证据（2026-08-09 至 2026-08-11）

- 状态: R1 已闭环。R1.0 接入决策、R1.1 生产加载链路 7/7、R1.2 自动化 4/4、R1.3 真实设备矩阵 7/7 及 R1 三项退出条件均已完成；默认关闭、显式同签名 exact component、单次失败回退与取消不回退语义保持不变。
- 默认与回滚: provider 设置默认关闭，只能显式选择同签名 exact component；启用后仅 raw `runtime.loadJar()` JAR 优先远端，失败至多回退一次内置 D8/dx，用户取消不回退，AAR 与 `defineClass()` 继续使用内置路径。
- 回退与 ownership: 宿主保留同一输入快照、输出事务、独立验证、host-only copy、原子 cache 发布与回滚 ownership；插件不能直接发布可加载产物。R1.2 源码在认证握手并最终化 semantic key 后、claim FD 与 `openSession` 前查找持久 cache，命中仍使用当前 validator 复验。
- 协商与身份: 协议版本和当次 runtime library fingerprint 在 Binder 握手后用于最终化请求，capability/ceiling 用于验证或拒绝；最小宿主构建号、固定 component/UID/signer 及同签名要求继续生效。
- R1.0 基线门禁: 从宿主 `85373a59c` 创建临时 detached worktree并运行 DEX 定向测试；10 个 suite、105 个 test，failure/error/skipped 均为 0。该结果只属于 R1.0 基线，不能替代当前 R1.1 代码与主门禁确认。
- R1.1 门禁: API 34 上 `DexCompilerProductionRoutingAndroidTest` 8/8 通过，覆盖 raw JAR opt-in 与单次 fallback、兼容 JAR/AAR/DEX/`defineClass()` 内置路由、固定决策快照、verified adoption 失败后的精确淘汰与回退、取消不启动本地编译、同 key 并发及探针故障隔离；持久证据位于 `D:\idea-projects\.bak\AutoJs6-DEX-R1-Evidence-20260810\production-routing-api34-8a479f65-bba1-4163-aded-00bf210e8ca9\report.json`，SHA-256 为 `9de8dff6f06fd1f16dd078199335b21e69c584a24455892b5ef318e3ec180737`。宿主 DEX 16 suites/149 tests、wire 4 suites/24 tests、fake-provider 5 suites/25 tests 全绿；fake provider 只承担故障注入，真实端到端结论由 API 31 lifecycle/concurrency/corpus 和 canonical 7-cell Gate 支撑。
- Cache 源码与测试: 已部署 generation manifest/checksum、严格 fsync/原子 commit、16 MiB 单项/128 MiB 总量/32 项、恢复/LRU/损坏精确淘汰及 descriptor 同 inode 复验。持久 cache 的 11 项 pure JVM、production Runtime single-flight 的 14/14 pure JVM、独立 Harness 52 项（含 6 项 cache 路径）与真实设备的同 key 合并、fresh caller capability、命中及 exact cleanup 共同覆盖 key、hit、single-flight、atomic publish、corrupt eviction 和 retry，满足 R1.2 cache 项。
- R1.2 JVM/编译门禁: 当前修正版宿主 DEX 16 suites/149 tests 全绿；Android test Kotlin 与 host/test APK assemble 成功。真实设备方法使用 host arm64 APK `181E38E8…A0A47`、严格修正版 test APK `70FAE1E8…39B0C` 与修复后插件 APK `5B6AC53B…640C4B`；三者 v2 signer certificate SHA-256 均为 `31a681fc…c213`。
- 新增 Android 方法: 2 个 production concurrency 方法覆盖相同 semantic key 的共享 producer/独立 capability，以及 follower 中断而 leader 继续发布；探针在宿主完成 committed remote dispatch 时计数，不把 provider `openSession` 的直接调用次数伪装成生产语义证据。2 个真实 lifecycle 方法覆盖阻塞 session 的 BUSY/FD/terminal，以及显式 force-stop 的 Binder death、pipe EOF 和 exact recovery。3 个真实 corpus 方法覆盖 Java/Kotlin single-dex 与重复加载、缺失依赖的 ART 解析边界，以及真实 D8 multi-dex。
- 重型 multi-dex 边界: 该 corpus 在运行时生成 7,300 个 class，每个含构造器和 8 个静态方法，共 65,700 个方法；输出解析每个真实 DEX 的 header、map 和 class_defs，并从 `classes.dex`、`classes2.dex` 各动态选择并执行一个生成类。它作为独立门禁在 21.692 s 内通过，不能泛化为其他 API/ABI。
- API 31 arm64 真实插件结果: same-key committed dispatch/fresh capabilities 1.479 s；follower interrupt/leader publish 0.583 s；BUSY/FD/callback/gate-reuse 严格修正版 2.177 s；Java+Kotlin single-dex/duplicate identity 0.555 s；missing dependency ART boundary 0.524 s；65,700-method multi-dex primary+secondary load 21.692 s；Binder-death/EOF/no-provider-terminal/rebind 严格修正版 1.355 s。各项均 PASS，测试后 workspace 为空；最终 host/test/plugin 卸载均 `Success`，fake provider 保持 absent，相关进程数为 0。
- R1.3 canonical Gate: campaign `f3c2b1af-be93-41e7-b541-f167f90e5cc1` 的 `gate-report.json` 为 `passed=true`、canonical receipt 7/7、attempt marker 7/7，journal head `a5abaf62803c6277aa015563cf16f2771eb0ffa9f9a226a20e7ac835ed54581b`，runner SHA-256 `ca89ac1637e5c690ced9e2e2d0b3d35aecf5c32584c6816883a21c363f040057`，campaign identity `6b859228a4943d74ab67707fa6c9a785f77248768ec1a4807e5e214034383665`；报告位于 `D:\idea-projects\.bak\AutoJs6-DEX-R1-Evidence-20260810\runs\f3c2b1af-be93-41e7-b541-f167f90e5cc1\gate-report.json`。
- Canonical identity: clean host commit `e39023758e3a66a24f0ce90466b5bc77a503515d`、plugin commit `1f50d5333ab3a58c4c0f00fe06a20a5692aa3448`；host/test/plugin APK SHA-256 分别为 `505bc077ad3586b802ba41eec5b093a01b3e7be011e0de7bf0b83dbf0aa1b878`、`4199d54d2f0fa8bd96d3c67d3c7073bf20a0c6f51f8248d2727e2dd75a75da24`、`65e432a7b4866cfb3db0392b87ac60e3dbab9161acc232b42b57a66abf08bd88`，完整 signer certificate SHA-256 均为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`。
- 失败证据保留: campaign `74dc8c24-62fc-4dd6-ad55-e33af3d0787e` 在 API 26 因空 WCHAN 的清理解析失败而没有 receipt；campaign `4ee685d9-4631-4fd0-878f-fd87efd0c17b` 在 API 26/24/25 PASS 后因 process grammar 仍不够 fail-closed 而主动终止；campaign `e7e6c30e-9d8f-4c65-b808-4e8c676af899` 达到 6/7 后，因单用户 runner 无法安全处理 QV 的 user 10 而主动终止。三者均原样保留，没有被最终 PASS 覆盖或改写。
- 并发与熔断边界: 中断任一 caller 都返回取消且绝不切换到本地编译器；R2 已补齐最后 waiter 离开时的 leader-owned cooperative cancel，有其他 waiter 时 producer 继续。安全熔断一旦触发即在当前进程生命周期内保守保持打开，不声称能硬中止已阻塞工作。
- 文档门禁: 宿主 10 个 changelog JSON 与 10 locale 资源、本插件 10 个 README locale JSON 均纳入解析检查；两仓生成器连续运行两次并要求第二次无变化，最终结果见本轮交付报告。
- 证据层级: JVM、Android 编译/APK、API 34 production routing、API 31 Binder lifecycle/concurrency/corpus 与 canonical 7-cell 真实 provider Gate 分层记录；没有把静态、fake 或单设备结果提升为矩阵验收。
- 执行边界: 每条设备命令均绑定显式 serial；canonical 单元完成宿主/插件/test/fake provider 的前后状态、精确安装/卸载、进程与 workspace 清理复核。QV 多用户拓扑与同名前缀邻近包保持不变。
- 插件恢复边界: force-stop 暴露出旧进程留下的真实 session workspace，促成 R2 的 process-once strict canonical janitor；该恢复切片见下节，不能倒推为 R2.2 全部完成。

## R2: 诊断、取消与恢复

目标: 在不改变 R1 默认关闭、显式 provider 与单次回退语义的前提下，让失败可辨识、终止后绝不发布半成品，并允许后续请求从进程中断中恢复。

状态: 已完成，交付项 4/4，退出条件 1/1。provider 启动恢复、有界故障摘要、协作取消与统一终态均具备 JVM、构建及一个获授权 API 34 x86_64 目标上的代表性真实 provider 闭环证据。

### R2.1 有界故障摘要

- [x] provider 将实际编译失败映射为现有 V1 的有界 `severity/code/message` 及稳定 failure phase/error code；宿主显示经过截断和脱敏的摘要，未知信息保持缺失，不伪造 origin、位置或进度。

最小证据: 协议/API 与 plugin/host JVM 测试，加一个获授权 Android 目标上的真实 D8 失败用例。无需重新运行多 API/ABI 矩阵。

范围边界:

- API 26+ 由 `D8Command` diagnostics handler 收集真实 error；API 24/25 保持已验收的 `D8.main` CLI 路径，仅在失败终态合成有界分类，不声称采集完整 D8 输出。
- 宿主的最近失败摘要仅存于当前进程，只显示稳定枚举、分类和计数；provider 原始 message、路径、digest 与 requestId 不持久化、不进入设置摘要或默认日志。
- origin/entry/位置等需要扩展 wire schema 的诊断元数据移至 R3/V2。
- progress 只有在 `current/total` 可真实测量时才报告数值，否则只报告阶段；该规则保留为非门禁实现约束。
- 完整 D8 info/warning 采集是后续增强，不阻塞 R2 的有界失败摘要。

本轮证据:

- 插件定向门禁为 11 suites / 53 tests，failure/error/skipped 均为 0；新增 `D8DiagnosticCollectorTest` 5/5，lint 为 0 error / 27 warning，Debug APK 构建成功。
- 宿主 DEX 定向门禁为 17 suites / 152 tests，failure/error/skipped 均为 0；新增 `DexCompilerRuntimeDiagnosticsTest` 3/3，app Debug 与 androidTest APK 均构建成功，构建期间禁止版本号与时间自动写回。
- API 34 x86_64 `DEX_R1_API34_X64` 上的单一真实 provider 方法在 3.213 s 内通过：先证明损坏 class 的真实 D8 失败被有界分类、脱敏且未发布，再证明后续正常 JAR 可编译、被 `DexClassLoader` 加载并执行。运行前后 host/test/provider/fake 包与相关进程均为空，AVD 及 5588/5589 端口已释放；本证据不外推为新的 API/ABI 矩阵。

### R2.2 Fail-closed 终态与恢复

- [x] cancel、close、deadline、Binder/transport/callback 故障共享同一终态不变量：调用方只观察一个终态，终止后不得发布结果，不再需要的描述符被关闭，session gate 最终可再次接纳请求；single-flight 的最后一个 waiter 离开时协作请求 producer 取消，有其他 waiter 时不得取消且调用方取消仍不回退；deadline 使用单调时钟，已进入不可中断 D8 时只保证禁止发布与最终清理，不声称 CPU 已停止。
- [x] provider 进程重新启动时，在首次 Binder 暴露前以 strict-canonical、fail-closed 方式回收旧 session workspace，不删除进程内后续创建的活动 workspace；恢复后新的真实 D8/`DexClassLoader` 请求可成功且 workspace 保持干净。

最小证据:

- 终态项使用确定性的 JVM race/fault 测试覆盖最后 waiter 取消、有其他 waiter 时继续和 terminal/publication 竞态，再加一个真实 provider 的取消或超时 smoke；不要求四个内部阶段逐一设备注入。
- 恢复项复用现有 6/6 workspace-recovery、API 31 force-stop/Binder-death/rebind 和正常 D8 后空 workspace 证据。force-stop 暴露的旧 UUID 在首次恢复前存在，恢复后仅保留空 root；当前插件总门禁已更新为 12 suites/65 tests、lint 0 error/27 warnings 与 Debug assemble 成功，Release assemble 保留恢复切片落地时的已有证据。
- 卡住 worker 继续采用 process-local safety circuit 的保守策略，不声称线程 interrupt 已经终止 D8 CPU 工作；该约束不单列 checkbox。

本轮证据:

- 宿主 commit `e65bef44d` 让最后一个 waiter 以 leader-owned one-shot handle 协作请求取消；有其他 waiter 时 producer 继续，取消调用方不回退。请求早于/晚于 Binder handle 建立、replacement flight、late publication、fallback 关闭和 VME/interrupt 传播均由确定性 JVM 测试覆盖。
- 宿主 deadline 从 attempt 创建时以单调时钟计算，begin、dispatch 与 publication commit 在同一锁内让先登记的 cancel/Binder death 优先于后到 timeout；当前 DEX 门禁为 17 suites/166 tests，failure/error/skipped 均为 0，app Debug 与 androidTest APK 构建成功，版本文件无写回。
- 插件 commit `6e716af` 统一 terminal/stop/cleanup 的 exactly-once ownership；编码、回调、worker rejection、callback death-link 或 stop 动作抛错时仍先完成无 worker cleanup 并释放 process gate，VME 保持主异常。插件门禁为 12 suites/65 tests，failure/error/skipped 均为 0，lint 为 0 error/27 warnings，Debug APK 构建成功。
- API 34 x86_64 `DEX_R1_API34_X64` 上复用单一真实 provider lifecycle 方法，3.004 s 内完成 BUSY、调用方取消、描述符 EOF、单终态与下一 session gate 复用，`OK (1 test)` / instrumentation `-1`。host/test/plugin 安装前后均 absent，fake 保持 absent，相关进程为 0，AVD 与 5588/5589 端口已释放；本证据不扩张为新矩阵，也不声称硬中止已进入 D8 的 CPU 工作。
- 本轮设备 APK SHA-256 为 host universal `236e3de0e4bc267b085cc2ed73463af3f957a17dc0dfe3a258a699cfa064ce11`、host androidTest `15b9ddbdc9fe34c1ccac4ade40c8df804623d8b9e03d9eab1ff80cc91e23a7ed`、plugin Debug `a4a0666a8847995abab02f935817b8b4f67367cd71a54f96c0e62a9ffad7e194`；三者 v2 signer certificate SHA-256 均为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`。

### R2.3 最小闭环验收

- [x] 一个可复核的 R2 验收包覆盖三类代表性场景：一次真实编译失败、一次调用方终止（取消或超时）、一次远端/进程中断；每项记录终态、是否发布、FD/临时目录清理及下一 session 可用性。完整 hostile permutations 可由 JVM/fake provider 承担，真实 provider 只需一个获授权 API/ABI 的代表性验收，不建立新的设备矩阵。

本轮闭环证据:

- Canonical run `dab3f857-650d-4107-a3b9-941a1f7e02c2` 在 API 34 x86_64 `DEX_R1_API34_X64` 上为 `PASS`。真实 D8 失败观察到有界 `UseLocal(REMOTE_ATTEMPT_FAILED)` 且失败事务未发布，随后正常 JAR 经同一 production coordinator 发布、由 `DexClassLoader` 执行并返回 42；该方法没有伪造数值 FD baseline，使用 production ownership、transient 清理、空 provider workspace 与紧随其后的成功 session 共同限定 FD/清理证据。
- 调用方取消得到 exactly-one `Cancelled(REQUESTED/CLEANUP)`，BUSY contender 也仅有一个终态；没有 `Completed`，输出达到 EOF，caller/provider PFD ownership 与空 workspace 均通过，process gate 随后接纳 successor session。provider 进程中断得到一次 Binder-death transport observation、零 provider callback terminal、零 `Completed` 与输出 EOF；workspace 为空，随后 exact rebind、身份复核及认证握手成功。
- 稳定报告为 `D:\idea-projects\.bak\AutoJs6-DEX-R2-Evidence-20260811\closeout-api34-dab3f857-650d-4107-a3b9-941a1f7e02c2\report.json`，SHA-256 `5d1549b9d5207e5dcd1c62a3c2caf863a748f49b8f9f2582f66bb2898be98eba`；61-file manifest SHA-256 `927ee1abebe83a0901e7f767a56b377a2afd84a137d16b8d5d3784fcd54e639e`；runner SHA-256 `61437b2b2d7a02e35d43176a1c381a9fcd4b7fa540b5876ed9347661962c5f9e`。runner 共记录 52 条显式 serial 命令，preflight/postflight 均 clean，host/test/plugin/fake 最终 absent，相关进程、AVD 及 5588/5589 端口均已释放。
- 首轮 run `f9c772a9-0bbb-4cee-9b1d-6cbeeae31ebf` 原样保留为 `FAIL`：runner 在任何安装或场景命令前因 PowerShell Hashtable JSON 序列化错误终止，`scenarioCount=0`；它是 preflight/runner 缺陷记录，不是三类设备场景的失败，也没有被最终 PASS 覆盖或改写。

非门禁韧性附录保留全阶段取消、callback backpressure/抛错、宿主进程 kill、磁盘耗尽、cache 清理失败及卡住 worker 的扩展组合；这些项目用于持续加固，不阻塞 R2 退出。

#### R2 退出条件

- [x] 上述四项全部完成，当前源码测试/lint/build 通过；canonical 简中用户文档与 V1 开发者文档保持 default-off、单次回退及“结果终止与 CPU 停止不同”的准确边界。其他 README locale 的阶段状态翻译不作为 R2 退出门禁，可独立后续同步。

## R3: V1.1 有序编译期 classpath

目标: 在不改 AIDL、不改变 V1.0 单 JAR 行为的前提下，为显式入口增加“一个 program JAR + 有序编译期 classpath JAR”语义，并把同一冻结输入集合贯穿远端编译、本地回退、single-flight 与持久 cache。R3 优先交付一条真实可用的纵向路径，不把依赖解析、全故障排列或新设备矩阵设为退出门禁。

状态: 已完成，交付项 4/4，退出条件 1/1。

### R3.1 协议与传输

- [x] 共享 contract/codec 已定义并构建 V1.1 与 V1.0 并存语义：V1.0 继续把既有 `programFd` 解释为 raw JAR；V1.1 定义同一有界 PFD 中的 canonical input bundle，声明恰好一个 program 与有序 classpath 的角色、ordinal、大小、SHA-256、集合指纹及单项/总量上限，不携带路径或名称，也不修改 AIDL transaction。provider 的实际 bundle 提取与 D8 接线仍属于 R3.2，不由本项冒充完成。

当前证据: host commit `c0b833a54` 的协议模块 5 suites / 42 tests 全通过，V1.0 golden bytes 与 AIDL 保持不变；Release API AAR SHA-256 为 `4766af19ea414400177ba8541f753737c8bf40624cbfc866bb5442cc4b07fea5`。plugin commit `ab08f08` 已固定同一 AAR，并通过 12 suites / 68 tests 与 Debug APK 构建。该证据只关闭共享 contract/codec 和 provider D8 classpath seam，不代表远端 V1.1 已可用。

兼容边界:

- 本阶段的兼容承诺是跨 APK 的 Binder/wire 互操作；host 与 provider 各自打包同代 API AAR，不把新增 Kotlin/JVM 构造器误称为旧 AAR 的 binary drop-in replacement。
- legacy `runtime.loadJar()` 固定协商 V1.0，不因 provider 支持 V1.1 而改变 wire bytes 或 cache identity。
- 只有非空 classpath 的显式入口才请求 V1.1；旧 provider 或缺少 bundle capability 时不得忽略 classpath、不得远端降级到 V1.0，只能在未取消时执行一次同语义本地 D8 回退。
- capability 扩展使用旧 reader 可跳过的 optional tags；不得把新枚举塞进 V1.0 `inputFormats` 使旧宿主拒绝整个 provider。

### R3.2 宿主与 provider 纵向切片

- [x] provider 对 bundle framing、顺序、摘要及聚合预算 fail-closed，随后把 program 与 classpath 分别传给固定版本 D8；API 26+ 使用 builder classpath，API 24/25 保留 CLI `--classpath` 路径。输出继续由宿主二次验证、host-only 原子发布，插件不下载依赖、不请求网络权限、不执行生成的 DEX。
- [x] 宿主以私有冻结 snapshots 构造 bundle；有序输入集合进入 request、single-flight 与独立版本的 semantic cache key。cache hit 仍发生在 FD claim 前，远端失败/adoption 失败/default-off 的本地 D8 使用同一冻结 program+classpath 且至多一次；有 classpath 时禁止掉入会丢语义的 dx fallback。

当前证据: plugin commit `8ebd7ff` 已实现 V1.0/raw 与 V1.1/bundle 分流、固定私有路径、逐项/聚合预算及 ordered D8 classpath；正式 Gradle 为 13 suites / 72 tests 全通过，Debug APK SHA-256 `6f36eeb230643c8dfccfa40aca71310bfb0ebd4b6b7903b516d4ee12cbb13372`。host commit `4d2b7dfed` 提供 frozen input-set、canonical bundle、精确 V1.1 协商及 order-sensitive cache/single-flight identity；commit `a540e0f90` 又把同一 retained input-set 接入 AndroidClassLoader 的 D8-only 本地回退，覆盖 default-off、旧 provider、远端失败与 adoption 失败，取消后不发布或注册 loader，且不进入 dx。正式 Gradle 为 19 suites / 174 DEX tests 全通过，host universal Debug APK SHA-256 `0f85f8abb04ea017bda37675fada92888172559004afe19ce7717cdf3f60439b`、AndroidTest APK SHA-256 `d8a33bc233a1f95dc8914d716f300d4f3d437a76510c57c6036e33a44270d689`；版本文件未写回。上述证据关闭 R3.2；JavaScript 显式入口与设备验收由 R3.3 单独记录。

### R3.3 显式入口与最小验收

- [x] 新增不改变旧 vararg 行为的显式 `runtime.loadJarWithClasspath(program, ...orderedClasspath)`；classpath 只参与编译，不进入输出，也不自动装载。运行时类型必须已由最终 program loader 的 parent 提供；旧 `runtime.loadJar()` 创建的是 sibling loader，不能被冒充为该 parent。定向 JVM/build 门禁通过后，只在一个获授权 API 34 目标上用 parent-visible fixture 验证真实 provider classpath 编译、最终 `DexClassLoader` 执行和一次 V1.0 回归，不重跑七设备矩阵。

当前证据: host commit `2e439a973` 增加显式 Rhino 入口并保持旧 `loadJar` overload 不变；正式 Gradle 为 20 suites / 176 DEX tests 全通过，Debug 与 AndroidTest APK 构建成功，版本文件未写回。唯一获授权的 `DEX_R1_API34_X64` API 34/x86_64 目标上，定向方法 `DexCompilerRealProviderAndroidTest#api34RhinoClasspathEntryUsesRealProviderAndRetainsLegacyLoadJar` 以真实 provider PASS：parent-visible fixture 经 V1.1 编译和最终 `DexClassLoader` 执行，compile-only stub 未进入输出，同时旧 `runtime.loadJar()` 的 V1.0 路径仍成功。host/test/plugin APK SHA-256 分别为 `f2c3819135e0d83f5903c7dc5b495d6f607f9d8b22e95723acda17467e0eb8dd`、`874c8678acec802f96f3a4281c633737a55097919bfe149fe5bf42a9de97b1b9`、`6f36eeb230643c8dfccfa40aca71310bfb0ebd4b6b7903b516d4ee12cbb13372`。

代表性验收包位于 `D:\idea-projects\.bak\AutoJs6-DEX-R3-Evidence-20260811\classpath-entry-api34-fa6c21a7-7dda-4bee-9485-bf78906ed83c`。runner SHA-256 为 `0e5db5fe64656f2a3255b81beec590b87fb3d0e64f7568af5049e72af1e0ef88`，`report.json` SHA-256 为 `af55c196f90422bbafccc5ddd98cd064e6cd1763346363b08f1bcbc0c12cbc40`，`files.sha256.json` SHA-256 为 `b4759c7fde31bfca866fbd02d4ac719c1193498b06df7cb6fadb574534fadf5e`，instrumentation stdout SHA-256 为 `dfcdcdf1ac2e89dced922081a8f7c05cfc8830c287808a3c61c12c64c50feb18`。证据包共有 117 个 physical files；manifest 自排除后覆盖 116 entries，hash/path diff 均为 0。报告记录 55 commands / 45 条显式 serial ADB 命令 / timeout 0，3 次安装与 3 次卸载成功，instrumentation 精确结果为 `OK (1 test)`、terminal code `-1`，pre/post 各 8 个 package probes 均为空且 cleanup failure 为 0。该结果只是一条 API 34/x86_64 代表性纵向证据，不是新的 API/ABI 矩阵，也不把 R3.2 的 JVM/build fallback 覆盖提升为全故障设备证明。

确定失败策略:

- bundle framing、摘要、顺序、数量或资源预算错误在 D8 前拒绝；输入之间同名的规范化 `.class` entry 可在验证阶段拒绝，但不把 entry 名比较冒充完整 classfile identity 分析。
- 缺失依赖、冲突类型和 unsupported bytecode 不在 R3 自造完整 classfile 解析器；由固定 D8 版本给出有界 `COMPILATION_FAILED`/diagnostics，编译成功仍必须经过宿主 DEX 校验和实际加载。compiler/runtime/input identity 均进入 cache key，避免把不同语义结果合并。

非门禁后续项: ordered multi-program 自动打包运行时依赖、显式 dependency parent/combined loader、AAR/资源处理、Maven/Gradle 解析或下载、自定义 desugared-library configuration、完整 duplicate/missing/conflict hostile permutations、全 API/ABI 矩阵及 R8。它们只有在形成独立稳定语义时再升级协议，不阻塞本轮 R3。

#### R3 退出条件

- [x] 上述四项完成；canonical V1.1 开发者文档与简中用户文档准确说明 default-off、compile-only classpath、同语义单次回退及 V1.0 兼容边界，并保留一个可复核的代表性设备验收包。

## R4: 编译器治理与能力分离

目标: 让 D8 provider 保持单一职责，并把高风险或不同产物语义的能力放到独立、显式选择的边界中。

### R4.1 D8 升级与确定性

- [x] 建立涵盖 Java/Kotlin 版本、desugaring、multi-dex、编译参数 minApi 24-36 和已知失败语料的 D8 升级矩阵。
- [x] 每次升级记录 D8 版本、输入摘要、runtime fingerprint、输出摘要和行为差异。
- [x] 在没有重复构建证据前不声明 deterministic；若无法保证，则 cache key 必须包含 compiler identity/version。
- [x] 为旧 D8 保留可回滚版本和兼容性说明。

R4.1 本轮实现与证据（2026-08-13）:

- 版本治理: 默认 D8 仍由 version catalog 固定为 `8.13.17`；catalog pin、matrix pin、构建生成的 `BuildConfig.D8_COMPILER_VERSION`、provider capability 与 `com.android.tools.r8.Version` 形成交叉核对。候选只能通过显式 `d8CandidateVersion` 属性覆盖，并由 Gate 记录 `CANDIDATE_OVERRIDE`；撤掉属性只表示撤销候选评估并恢复 `PINNED_BASELINE`，不需要改源码或发布声明，也不冒充默认 pin 的 promotion/rollback。当前宿主 `DexCompilerSemanticCacheKey` 继续把 compiler family/version 与 runtime fingerprint 编入 canonical key，既有定向测试覆盖任一版本变化都会改变 key；本轮只读复核该源码与测试，未改宿主。
- 本地矩阵: `r4.1-g1-d8-upgrade` 共 60 个 JVM/compiler-only cell。Java 8 覆盖 minApi 24-36 的 DEBUG/RELEASE，Java 11/17/21、当前 Kotlin 2.3.20/JVM 21、标准 desugaring、生成式 multi-dex、缺失运行时依赖引用、畸形/超前 classfile 与重复定义按代表性边界展开。`minApi` 是 D8 编译参数，不是设备 API 矩阵；缺失依赖 cell 只证明 D8 保留外部类型引用并成功编译，不冒充 ART 运行时解析。
- 报告与门禁: 每次专用 `r4D8UpgradeMatrixTest` producer 都使用新的规范 UUID 与独立 invocation 目录；v2 cell report 和 v2 Gate 绑定该 UUID，固定 gate 在 task graph/producer 启动前先原子失效，因此无关 `--tests` 过滤、producer/JVM 失败或旧 60-cell 目录都不能留下或重新消费旧 PASS。每个 cell 记录 compiler version、输入 SHA-256、同一 `android-36/android.jar` runtime fingerprint、编译结果、输出摘要和连续 `classes*.dex` manifest；成功 cell 精确运行两次，失败 cell 保留一次真实拒绝。consumer 固定 11-case/60-cell 形状，并拒绝缺/重复 cell、跨 invocation 混入、版本漂移、摘要缺失、非法 deterministic 声明、重复次数不符、DEX 乱序/缺号和候选 DEX 拓扑变化。Gate/比较器绑定 producer UUID、matrix/schema/report-set SHA-256；无模块 bootstrap 在 gate module 导入前建立安全输出，所以模块缺失/损坏或 expected UUID 缺失/畸形也会原子替换旧 PASS。输出不得经直接、祖先 symlink/junction 或 hardlink 别名覆盖输入，错误结果不持久化本机绝对路径。当前治理脚本固定自测为 29/29 PASS；历史稳定包中的 22/22 属旧 v1 治理快照，不冒充当前 v2 证据。
- 固定基线: 当前组合源码的 `:app:verifyR4D8UpgradeMatrix --rerun-tasks` 为 60/60 PASS；去掉 `--rerun-tasks` 后再次运行时，专用矩阵 `Test` 与 Gate 仍实际执行而非 `UP-TO-DATE`/`FROM-CACHE`，且两次 producer UUID 不同。最终 Gate invocation 为 `bd2c21e1-7061-4206-8464-cb12c48dae7c`，SHA-256 为 `fe52f9b3571f5b08ce298449d7ae6d01e638f758b222ad18dc2851fce51683b1`。54 个成功 cell 均双跑且在本机摘要一致，6 个已知失败 cell 由真实 D8 拒绝；4 个 multi-dex cell 均产生 `classes.dex` 与 `classes2.dex`。所有报告仍固定 `determinismClaim=NOT_CLAIMED`。历史稳定包的 14 suites / 76 tests、v1 baseline/candidate 与 lint/APK 继续作为 2026-08-13 快照保留，不覆盖本轮 v2 fresh-invocation 证据。
- 候选演练: 使用 PowerShell 原生参数数组显式评估 `8.13.22`，候选 60/60 PASS；相同输入摘要、runtime fingerprint、compiler outcome 和 DEX entry-name 结构下，全部 54 个成功 cell 的输出字节摘要相对 `8.13.17` 改变。比较器原样记录差异而不声明确定性或字节等价；默认固定版本没有升级。
- Android 构建层: 回到默认 `8.13.17` 后，`:app:lintDebug :app:assembleDebug` 成功；lint 为 0 error / 27 warning，Debug APK SHA-256 为 `dcc5b97c0f4deb06d29fcc8c08cb7bb3c85dd01655d0809b65c117948320534b`。报告位于 `app/build/reports/d8-upgrade-matrix/`、`app/build/reports/tests/testDebugUnitTest/` 与 `app/build/reports/lint-results-debug.html`。
- 稳定证据包: `D:\idea-projects\.bak\AutoJs6-DEX-R4-Evidence-20260813\r4.1-g1-local-matrix-42ebd253-8097-418e-b2a8-3ccaaeeb62ae`；`report.json` SHA-256 为 `30afdb13c53297d0675680e4d51a71db971431ebc216e467465c9ac1c7d8ad14`。该包保留两套 cell/gate、绑定比较、无 `--rerun-tasks` 仍实际执行矩阵的 console transcript、治理自测、14 份 JVM XML、lint/APK 结果、源码快照、失败候选命令和自排除 SHA-256 manifest；共 185 个 physical files，manifest 覆盖 184 entries 且 hash/path diff 为 0。包内报告只声明 `JVM_COMPILER_ONLY_AND_ANDROID_BUILD`。
- 证据边界: 本轮没有运行 ADB、`connected*`、安装、Binder/PFD、跨 APK、真实 `DexClassLoader` 或设备任务，也没有触碰 `QV710AF65F`。因此 R4.1 只关闭本地升级治理，不能替代任一 API/ABI 设备验收；R4.2/R4.3 与 R4 总退出条件保持未完成。

R4.1-G2 默认晋升、旧 pin 回滚与再晋升收口（2026-08-25）:

- 构建身份先迁移到 Maven Local 的 `org.autojs.build:autojs6-gradle-platform-versions:1.4.1`；发布 JAR 为 82,427 bytes、SHA-256 `028ee9e96386e642313abb4d1904455959b87236f26a7ecaf8cd3bba35f2d9e8`，与 sibling source commit `dcf5d9a6b0de56fef34fcf6929478d86b1693fd0` 的 fresh `test jar --rerun-tasks` 输出逐字节一致。DEX 在 `--offline` 下解析 Gradle 9.5、Kotlin 2.3.20、AGP 9.2.1 与 AGP bundled R8 8.13.19；该 bundled R8 仍只属于 Android 打包工具链。
- 矩阵 contract 升级为 invocation-bound v2、Gate v3；新增与 candidate override 互斥的 `d8RollbackEvaluation`，它只验证当前 catalog 是否精确回到旧 pin，不能选择依赖。治理/启动失败回归为 31/31，模块缺失、语法损坏、import-time 异常、无关 `--tests` 和 UUID 漂移均会在 producer 前后原子覆盖旧 PASS。promotion closeout 自测另为 10/10。
- campaign `5640aa27-6f53-408c-8d2d-b256c66a7d84` 在同一 normalized source/build identity `b04db0e68556bb4ba6033f0d580c6b7994e4f47e687d214ae96794f71883517e` 与 runtime fingerprint `d9eb9da824d9e247a352f570f01e1169e725b2954bca9e283a71786c59b59f9a` 下依次实际执行三套独立 60-cell producer：`PROMOTED_DEFAULT` 使用 catalog `8.13.22`，Gate SHA-256 `09b03c7141d431364c9f59c9a6ec4549395bb153c702b66666d74368ac69335d`；`OLD_PIN_ROLLBACK` 使用 catalog `8.13.17`，Gate SHA-256 `b34f759123f2ff097c862957dcd5ead26fd3912b82a751320c3d4058aafef15c`；`FINAL_PROMOTED_DEFAULT` 再回到 catalog `8.13.22`，Gate SHA-256 `566fa6c05f9b6f252ed5c46ee4a67898e4f3534b0cbfed17102ca7fd85fbf2d8`。三套均为 60/60、54 个真实成功与 6 个预期失败，producer UUID、Gate 与 report-set 均不同，且没有 candidate override。
- promotion closeout Gate 位于 `D:\idea-projects\.bak\AutoJs6-DEX-R4-Evidence-20260825\r4.1-g2-default-promotion-5640aa27-6f53-408c-8d2d-b256c66a7d84\promotion-gate.json`，SHA-256 `e65b2be5aabb5bb3d293621ea68ff481984d7ef700a9938cc33b77731c1eac45`。最终默认 pin 现为 `8.13.22`，仍固定 `determinismClaim=NOT_CLAIMED`；本 campaign 没有设备、签名、安装或远端操作。后续 R4.3 门禁/文档只增加治理面且不改变 D8 生产 engine；最终组合树又以 producer `f36d293f-fd50-4508-8a35-b15669ec292b` 强制重跑默认 60/60，Gate SHA-256 `e98e0373450dcc276aa7957e612c8f68beb0205569354586f33b20144fa34007`。

DEX 本地历史与隐私治理（2026-08-25）:

- `master` 原有 21/21 commits 的 author/committer 已统一为 `SuperMonster003 <30370009+SuperMonster003@users.noreply.github.com>`；逐提交核对 tree、message、author/committer name、日期和父拓扑保持不变，改写完成时 HEAD 为 `840a52cbf636767128a256b81ee134908ad1cf39`。仓库本地 `user.name`/`user.email` 同步为该身份，后续本地提交继续使用 noreply。
- 改写前恢复 bundle 为 `D:\idea-projects\.private-git-backups\AutoJs6-Plugin-DEX-Compiler\pre-noreply-20260825T142912.bundle`，740,881 bytes、SHA-256 `d2689f819dada88fd179b28aeec464ceae52f8136c49bafd8a6b3825b6c7ee6b`；改写后已过期 reflog 并 GC 旧对象。该 bundle 仅位于本机外部私有备份目录。
- 本 DEX 仓库继续仅本地部署：未创建 GitHub 仓库、未配置或推送业务远端、未创建 remote release。R8 sibling 的 Private 发布不能被解释为 DEX 的远端发布授权。

### R4.2 独立 R8 provider

- [x] `RELEASE` 继续只代表 D8 compilation mode，不静默等同于 shrinking、optimization 或 obfuscation。
- [x] R8 使用独立 provider identity、capability、协议语义、append-only 本地签名发布历史及 Private prerelease；未来 Public 转换仍是独立 Gate，不冒充已完成。
- [x] keep rules、consumer rules、mapping、seeds/usage 及 retrace 产物采用显式、有界接口。
- [x] 反射、动态类名、JNI、序列化和 AutoJs6 脚本访问建立专门兼容性语料。
- [x] 用户必须显式选择 R8；失败时不得悄悄退化为含不同语义的 D8 产物。

R4.2-G1 独立合同层（2026-08-14）:

- [x] 在独立 sibling `D:\idea-projects\AutoJs6-Plugin-R8-Compiler` 的初始提交 `2a1fb3b70cfe6f4678bd0118a87c905a3fe52bbd` 冻结 `r8-compiler-api` 0.1.0：独立 namespace、Action、engine/cache domain、协议 1.0、15 个 R8 schema、3 个 AIDL descriptor，以及仅允许 `R8_EXPLICIT` / `fallbackPolicy=NONE` / `FULL_RELEASE` 的 typed contract。
- [x] 冻结 path-free canonical input/artifact bundle、有界 program/classpath/keep/consumer rules、精确五产物 `DEX_ZIP/MAPPING/SEEDS/USAGE/RETRACE_METADATA`、runtime/capability/input/output SHA-256 绑定与 mapping provenance；`RETRACE_METADATA` 不是 retrace RPC 或执行证据。
- [x] 建立合同 hostile/JVM 门禁：13 suites / 126 tests（protocol-wire 14、R8 contract 112）全通过，含 TaggedWire、golden wire/bundle、provider 较小预算、dangerous directive corpus、摘要/产物交叉绑定、有界 adversarial collection/InputStream 语义和 4×256=1,024 个 fixed-seed mutation variants；两个 lint task 均为 0 error（R8 API 0 warning，protocol-wire 仅 1 条 wrapper-version advisory）。
- [x] 生成 append-only 本地 `0.1.0` 合同分发：严格 classfile golden 覆盖 97 个 class entries、87 个 Java-visible classes、774 个 visible members、10 个 AIDL method descriptors、3 个 Binder `DESCRIPTOR` 与 10 个 transaction constants，ABI golden SHA-256 为 `b628e1e2edccf0510b7acd31157fb9184947f1d8ccfe61826d0076e7350c96bf`。distribution mutation self-test 31/31、source-boundary self-test 43/43、真实 source gate 16/16；清单先 `CREATED` 再以同字节 `IDENTICAL` 复验。manifest SHA-256 为 `40c307e1280fa011064f4e7f06215ec17364bfe88cc74bfff5ae0a5d2827b16a`，protocol-wire/R8 API AAR SHA-256 分别为 `1d97a5b44b2c20e85aa12b263fca604a32d6d89275d47a19076861cd20c29a36` / `e9df49b7e49992615a15bc0af2372a4525f02b4a2a915a560ddab3128bb2f066`；共同记录的 source fingerprint 为 `a85d40e9e8eebbc347703588fef20adb0ee93a2d992425baca076635d79a3dc8`，verifier SHA-256 为 `3b12ecdd28187c577bcb3a80fd3d2c1e79988ad33dc5ddee1d93a674c0e3bf33`，本地 report SHA-256 为 `28425adc67ced736b434524c1708f35267d1fe2a9feeff9be8cb2f9e616815fd`。detached Java consumer 使用空 sourcepath 与仅 Android 36 及两个 AAR 解出的 `classes.jar` 编译成功；清单只共同记录 source snapshot 与独立扫描 artifact，不冒充 reproducible source-to-binary derivation。
- [x] 严格保留 `CONTRACT_AAR_ONLY` 边界：新仓库没有 `:app`、applicationId 实装、Manifest/service/provider、R8 engine dependency/调用、宿主接线、APK 或设备操作；报告固定 `published=false`、`pluginConsumed=false`，且 provider/manifest/host/Binder/R8/retrace/device claims 全为 false。

上述五项只关闭 G1 的 contract/AAR 子门；它们在冻结时没有可安装 provider、真实 rules/R8 执行、多产物生产者/消费者、宿主选择链或独立发布历史。后续 G2 已补上本地 provider/真实 JVM R8/五产物 producer，G3 v3 补上宿主 canonical 输入与五产物 consumer，G3 v4 又补上默认关闭的用户 exact-component 选择、`runtime.loadJarWithR8` 公开入口与只读 DEX 加载，G4 v1 再以 Java/Kotlin × `minApi` 24-36 的 26-cell 真实 R8 语料覆盖反射、动态类名、JNI、序列化和脚本公开面，G5 v1 建立同签名、append-only 的本地 APK/API 历史与双隔离构建复现证据。G6/G7/G8 随后分别关闭跨 APK Binder/PFD 设备验收、ART/JNI/Retrace 与隐私归一化 Private prerelease；历史报告各自保持原边界，不把后续证据倒灌进 G1-G5。

R4.2-G2 本地 provider 纵向切片（2026-08-24）:

- 独立实现: sibling 当前工作树新增独立 `:app`，application ID 为 `io.github.supermonster003.autojs6.plugin.r8compiler`；Manifest 只导出一个受 `org.autojs.permission.PLUGIN` 保护的 `.R8CompilerService`，固定 discovery Action `org.autojs.plugin.R8_COMPILER` 并运行于专用 `:r8` 进程。provider 直接消费 G1 冻结的两个 0.1.0 AAR 字节，不以 project dependency 回落到合同源码；同签名 exact AutoJs6 caller、provider ID `autojs6-r8`、engine/cache/protocol 域保持独立，生产源码静态拒绝 D8/dx 路由。
- 输入与执行: provider 在私有、启动可恢复的 session workspace 中完整读取 canonical input bundle，复验单项/集合摘要、ZIP EOCD/central/local 视图、规范 entry 名、class magic、压缩比及单项/聚合资源预算，并在 bundle 完整 EOF/digest 成功后才把显式 keep/consumer rules 交给固定 R8 `8.13.17`。API 26+ 使用 `R8Command`、`CompilationMode.RELEASE`、tree-shaking/minification enabled 与 cancellation checker；API 24/25 CLI seam 固定 `--release` 和 provider 自有 report destinations；两条路径均无 D8/dx fallback。
- 五产物事务: R8 输出先在私有目录验证连续 `classes*.dex`、DEX header/signature/checksum，再生成并规范化 `DEX_ZIP/MAPPING_TEXT/SEEDS_TEXT/USAGE_TEXT/RETRACE_METADATA`；mapping provenance 绑定 compiler/capability/runtime/input/minApi/profile。五份产物先写成一个本地 canonical artifact bundle 并复验大小/摘要，成功后才单次 claim/write caller output FD；任一失败、取消或超时保持 R8 terminal，不能发布半成品或切换语义。
- session 安全实现: service 启动清理 canonical stale workspaces，进程级 gate 只允许一个 active session；输入必须只读、输出必须只写且 `fstat` 不可 alias，API 24-29 的 access flags 从有界 `/proc/self/fdinfo/<fd>` fail-closed 读取。callback 串行且有界，UID owner/caller 每次复核，Binder death、取消、close、deadline、service destroy 与清理均由 exactly-once terminal controller 收口；R8 的 cooperative checker/线程中断只阻止后续发布，不把“请求停止”冒充已经强杀编译器。
- 本地门禁: `verifyG2Provider` 固定先原子失效旧 Gate，再依赖 provider JVM、lint、Debug/Release APK。v2 最终 invocation `d7a5116d-8fe4-4140-baf7-4d5a594402f7` 带动 98/98 tasks 实际执行；6 suites / 41 tests 全绿，其中原有 15 项继续覆盖动态 javac JAR 的真实 JVM R8、冻结 contract 对五产物反向消费、聚合输出预算拒绝、API 24 CLI 边界、恶意规则/输入、workspace/gate/terminal、identity/Manifest/AAR 字节检查，新增 26 项属于后续 G4 Java/Kotlin 兼容语料，纳入全量 prerequisite 不会扩张 G2 的 Binder/设备证据边界。lint 为 0 error / 2 个版本边界 warning，Debug 与 unsigned Release APK 均成功构建。最终 Gate SHA-256 为 `fa2c9650f1673b16f7e067e6a9ea3cd758f435741e34aa7a2e0e80b451d699f8`，自记录 verifier SHA-256 为 `0526ca1ab259166e8051faa8c97ac42c190f403d4b202f51ebde2cf47d4035ac`；Debug/unsigned Release APK SHA-256 仍分别为 `c1abf688fb421297b3a5850bb995f66aa3ab42cd1498e398268abc1119182b5b` / `abf64169280592153909f6175702648f05e89201d1baa675d9689f729e56c5d9`。无关 `--tests` producer 故意失败后固定 v2 Gate 保持 `passed=false`（SHA-256 `04e613f76bb6ac94d877560cca93a689d08265161d319f3a8d0bf00469ffb1d1`），随后才恢复正向 PASS；报告无工作区绝对路径。当前 mutable identity 已进入后续 G3/G4 状态，G2 report 因而显式记录 `laterHostIntegrationPresent=true`、`extendsThisG2EvidenceBoundary=false`，自身 `hostIntegrated` claim 仍为 false。冻结 G1 合同另行重跑为 13 suites / 126 tests 全绿。
- 证据边界: 当前 Gate 固定声明 `LOCAL_PROVIDER_JVM_AND_ANDROID_BUILD`。本轮未运行 ADB、安装、`connected*`、真实 Binder/PFD、进程死亡或设备任务，未触碰 `QV710AF65F`；Release APK 未签名、未发布，provider 也没有独立远端发布历史。因此该 Gate 只关闭 sibling G2 的前两项；G2 第三项仍未完成，后续 G3 宿主事务证据单独记录如下，不能倒灌为 G2 Binder/设备证据。

R4.2-G3 宿主显式集成切片（2026-08-24）:

- 冻结消费边界: sibling `AutoJs6` 的最终 Gate 基于 commit `afca7b14c4ba3971b60a9ce3587e2f10bfd0ab1e` 当前工作树，新增本地 AAR wrapper 并实际消费 G1 冻结的 `r8-compiler-api-0.1.0.aar`，SHA-256 仍为 `e9df49b7e49992615a15bc0af2372a4525f02b4a2a915a560ddab3128bb2f066`，没有 composite/source-project dependency。宿主显式依赖的 protocol-wire `TaggedWire.kt` 与 G1 source snapshot 同字节，SHA-256 为 `5d5c672ef0c7907b1a0cf6fd041ff85dc7c864aa07628316db5b9a9abb9e87c8`。
- 默认关闭与精确选择: R8 使用独立 Developer options preference 与偏好键并默认关闭；用户必须在专用选择器中选择一个 eligible exact component。选择器只查询 `org.autojs.plugin.R8_COMPILER`，要求 exact component、exported/enabled、`org.autojs.permission.PLUGIN` 和 host same-signature；选择阶段固定 component、UID、version、lastUpdateTime 与完整 signer digest 集合。Android 适配器只以显式 `ComponentName` 绑定，连接后再次检查 exact package identity，再固定 provider ID `autojs6-r8`、protocol 1.0、`R8/FULL_RELEASE/NONE`、runtime/policy fingerprint 与精确五产物 capability；callback UID 必须等于固定 package UID。
- 公开入口与加载终点: 新增且只新增 `runtime.loadJarWithR8(...)` 三个有效 overload；最短形状也必须传非空 keep-rule 路径，完整形状显式传 ordered classpath、consumer-rule 路径及平行 classpath owner ordinal。Rhino 已实测脚本数组到 `String[]/int[]` 的转换，现有 `runtime.loadJar()` 与 `runtime.loadJarWithClasspath()` 语义不变且不会隐式选择 R8。五产物全部验证后仅 `DEX_ZIP` 可进入 class loader；加载器再次核对 size/SHA-256，原子采用只读 `r8_verified_` 副本，该 seam 不调用本地 D8/dx compiler。
- 宿主事务与 D8/R8 隔离: 专用阻塞 dispatcher 在显式选择后完整快照有界 program/classpath/keep/consumer rules，生成 path-free canonical input bundle 与仅允许 protocol 1.0、`R8_EXPLICIT/FULL_RELEASE/NONE`、精确五产物的请求；宿主持有独立只读/只写 descriptor、callback/timeout/cancel/Binder-death gate、输出 staging 与清理。completed 结果必须重新验证 result/bundle、五产物大小与 SHA-256、文本/retrace 约束以及连续 `classes*.dex` 的 header/signature/checksum，才可进入 R8-only cache。生产 R8 源码不 import DEX host transport、`dex-compiler-api` 或 D8/dx 路由。
- 原子 cache 与失败防火墙: R8 semantic key 使用 domain `autojs6:r8-compiler:v1` 与目录 `r8-compiler-cache-v1`，绑定 provider/signer/version、protocol、compiler/capability/runtime fingerprint、input-set、minApi 及输出预算。验证产物先复制到 `partial-<uuid>`，只以同目录 rename 暴露 `entry-<semantic-sha>-<uuid>`；cache hit 重绑当次 request ID、复验 bundle/产物并在每次打开 descriptor 前再次计算 SHA-256。损坏 generation 被淘汰并只重试同一显式 R8 provider；远端失败、取消、超时、Binder death 注入、畸形/重复 callback、损坏 bundle/DEX、descriptor/session cleanup 与 cache lookup/publication 失败均保持 R8 failure，`semanticFallbackAllowed=false`。
- invocation-bound v4 门禁: sibling R8 仓库的 `verifyG3HostControlPlane` 先原子覆盖固定报告为 `passed=false`，再以 `--no-daemon --rerun-tasks` 强制执行宿主专用 Test。最终 verifier 字节传入不存在的宿主根目录时，阴性 invocation `7af8ecdf-3cb8-41bb-a954-7db98fc081d6` 退出 1 并留下 `passed=false`；紧随其后的正向 invocation `df92acbe-6c63-4f75-91dd-0a6a6522407b` 实际执行 537/537 tasks，以 11 suites / 49 tests 全绿。最终 Gate SHA-256 为 `8f3fa7ce908547ebd3647c3073d4803addb4982582f1c0c4af28046124478eab`，self-recorded verifier SHA-256 为 `579cc569791205e89ad7acba3d30bdcee5a1e9bce45aa7e6bd56bc7f34158d79`；报告固定 25 个 production、13 个 test sources 与 15 个外部 integration/resource files 的摘要，且不含两个工作区绝对路径。
- 宿主打包补充检查: `:app:assembleAppDebug` 成功，当前 mixed-workspace universal APK 为 43,991,748 bytes，SHA-256 `3fb6642c88e62a99411bd7c266d537f793c54d3339896792b6b22fbb1fee9dc6`；`apkanalyzer dex packages --defined-only` 检出宿主 R8 package、冻结 R8 API package 及精确的 2/3/5 参数 `loadJarWithR8` signatures。该 APK 未安装、未发布，也不是固定 G3 Gate artifact。宿主日志中的 bundled R8 `8.13.19` 是 AGP 的 APK/D8 打包工具链，不是 provider compiler identity；provider 仍固定 R8 `8.13.17`。
- 文档与声明: 在线文档 125 modules 重新生成并通过 normalize/generator `--check`，不增版本地同步 Offline Docs 的 `runtime.html` 与 search index；TypeScript Declarations 与 Ace bundled declaration 的完整文件 SHA-256 均为 `f571ed5a13f5fad9416a134c3ca29fcf327f90ceded1c6c3efa70f362fcb986e`，`tsc --noEmit` 通过。它们只证明本地公开面同步，不是发布证据。
- 证据边界: v4 Gate 固定声明 `HOST_R8_EXPLICIT_SCRIPT_INTEGRATION_JVM_AND_ANDROID_COMPILE`，准确设置 `hostIntegrated=true`、`publicOrScriptEntry=true`、`runtimeDispatchImplemented=true`、`postDispatchRunnerVerified=true`、artifact adoption/persistent R8 cache 为 true，同时保持 `binderVerified=false`、`deviceVerified=false`、`published=false`。因此 sibling G3 三项本地实现门均关闭，并关闭 R4.2 的显式有界 rules/artifacts 与用户显式选择/no-fallback aggregates；后续 G4 已另行补齐本地兼容语料，但跨 APK Binder/PFD、设备、安装、发布及 R4 总退出仍未完成。本切片未运行 ADB、`connected*`、安装或设备任务，未触碰 `QV710AF65F`。

R4.2-G4 本地兼容性语料（2026-08-24）:

- 26-cell 真实编译矩阵: sibling R8 仓库新增 Java/Kotlin 两种输入 × R8 编译参数 `minApi` 24-36 的完整 2×13 矩阵。Java 程序由 `javac --release 8` 动态生成，Kotlin 程序取项目实际编译 class 并显式提供有界 Kotlin runtime/annotation classpath；每个 cell 都经过生产 `R8InputMaterializer`、固定 R8 `8.13.17`、`R8ArtifactPackager` 与 canonical artifact codec，输出精确的 `DEX_ZIP/MAPPING/SEEDS/USAGE/RETRACE_METADATA` 五产物。这里的 `minApi` 只是 R8 编译参数，不冒充 API 24-36 设备矩阵。
- 五类兼容观察: 每种语言程序同时携带常量反射目标、由运行期参数拼接的动态类名、JNI native 方法、带 `serialVersionUID/writeObject/readObject/readResolve` 的序列化状态，以及供 AutoJs6 脚本后续访问的 public constructor/instance/static API。原始 JAR 先在隔离 JVM loader 中执行反射、动态类名、序列化 round-trip 和 public API control，JNI 只反射检查 native modifier，不调用 native。R8 后解析真实 indexed DEX 的 header/string/type/field/method/class tables 与 encoded class-data，核对类定义、成员、native flag；同时检查 mapping、seeds、usage 和连续 DEX topology。未 keep 的 `RemovedDecoy` 必须从 DEX 消失并出现在 usage，防止通过全局关闭 shrinking 伪造兼容。宿主另行强制复跑 8/8 Rhino/runtime route 测试。
- invocation-bound v1 门禁: G4 verifier 在任何 child Gradle 前原子失效固定报告并清空旧 receipts。不存在的 provider test filter 阴性 invocation `cf14a5e4-0d3a-4e69-90a3-c19bdeba70e9` 在 Test producer 退出 1，旧 receipt 数为 0，固定报告保持 `passed=false`，SHA-256 `29029766d7fec9b08c10e54f59cd35a310793e471aa5b3c2468267de9b5dce28`。随后正向 invocation `dd2ddb3d-3b24-4580-9d55-34a5c3e13f07` 通过 provider 26/26 与 host 8/8，宿主 child 实际执行 537/537 tasks；26 份 path-free receipt 共 50,037 bytes，逐份绑定 program/rules/input/output/five-artifact 摘要且固定 `determinismClaim=NOT_CLAIMED`。
- 最终证据与边界: G4 Gate SHA-256 为 `ba2dc55bc592bca0d5247438be7cfdea919f33ea841a6fbaa1a34a1c70326ca0`，self-recorded verifier SHA-256 为 `ea92853a859982dfc2d528585088a1f6452a578a1602f2453e1df3b2d6bf2640`；它绑定当前 G2 report `fa2c9650f1673b16f7e067e6a9ea3cd758f435741e34aa7a2e0e80b451d699f8`、不变的 G3 report `8f3fa7ce908547ebd3647c3073d4803addb4982582f1c0c4af28046124478eab`、4 个 corpus files、2 个 host route files、design、verifier 与 26 receipts，独立重哈希 34 records 为 0 mismatch，报告/receipts 均无仓库绝对路径。Gate 固定声明 `R8_COMPATIBILITY_CORPUS_JVM_ARTIFACT_AND_SCRIPT_ROUTE`，只关闭 R4.2 的兼容语料项；`postR8DexRuntimeExecuted=false`、`jniLinked=false`、`binderVerified=false`、`deviceVerified=false`、`published=false`。未运行 ADB、安装、`connected*` 或设备任务，未触碰 `QV710AF65F`。

R4.2-G5 append-only 本地签名发布（2026-08-25）:

- 双隔离构建与签名: sibling R8 仓库的固定 `publishG5LocalRelease` 入口把当前 staged/untracked 非忽略工作树复制到两个不同临时目录，各以 `--offline --no-daemon --no-build-cache --no-configuration-cache --rerun-tasks :app:assembleRelease` 实际执行 46/46 tasks。两份 unsigned APK 均为 7,518,691 bytes、SHA-256 `79c53c72066d9f319b22957e790d9d5f4685c6fddbd1078bdb3ef30d9d35d2b1`；使用获授权 AutoJs6 主项目签名材料各自独立签名后，两份 APK 均为 7,526,791 bytes、SHA-256 `bf2401cc585aaee1f39485c086ccdbb21eb70aca0d83f5e20fd67e1f46b41e0b`。`apksigner` 在 API 24-36 验证唯一证书 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`，v2/v3 为 true，v1/v3.1/v3.2/v4 为 false；post-sign manifest 的 package/version/SDK/permission/service/`:r8`/action 均精确匹配。这只证明同一离线机器/工具链下两个干净目录的字节复现，不声称跨环境 hermetic reproducibility。
- 本地历史与失败关闭: authoritative `releases/provider/0.1.0-provider-dev/local.2/` 恰好包含 signed APK、两个 G1 冻结 AAR 和 manifest；manifest SHA-256 为 `4e95ea6c214016a7fd598419c34628ba20d4ff94b22264349085fe9d6c2d07e1`，绑定 48 个 release inputs/source fingerprint `111f25080513c934b9e6b52d9ea2be77ea47356e70324a262ec5c8dfb81fc0fc`。bootstrap `local.1` 因 Gradle 子 PowerShell 暴露 `Get-FileHash` module-autoload 依赖而由 module-independent .NET SHA-256 的 `local.2` 取代，但其 4 个字节冻结文件保持不变。`local.2` 创建后，错误 source fingerprint invocation `e958afa2-3fb0-44e9-b7e0-93b264804d25` 在构建/签名前退出 1 并覆盖 Gate 为 `passed=false`，SHA-256 `7e2371343d91f29926be1934661d8e140adb8ae3186d9700fdefcef2bdbaa1a0`，两代共 8 个文件逐哈希未变；最终 invocation `51112028-ae46-4174-b58e-18da96750d15` 再跑两套 46-task build 后只返回 `IDENTICAL`。最终 Gate SHA-256 `68a9220fcb16f50c60c6812faea56d1a25faf6674bd29e758e5ed64afbb41d94`，publisher SHA-256 `c12879b5c7f37d7d490ba124bb3ecee22c538fb044b899121ead7d55c7b4658b`。
- 秘密与边界: 密码只经子进程环境变量传入并在 `finally` 清空；manifest/Gate 无密码、实际 alias、外部绝对路径、keystore/properties 文件名，发布目录无 partial，系统临时目录无 G5 残留。报告固定 `localPublished=true`、`remotePublished=false`、`gitPushPerformed=false`、`remoteReleaseCreated=false`、`remoteMavenPublished=false`、`adbInvoked=false`、`installed=false`、`binderVerified=false`、`deviceVerified=false`。这关闭 R4.2 第五个本地 aggregate，但不替代获授权跨 APK Binder/设备验收，也不关闭 R4 总退出条件。

R4.2-G6/G7/G8 设备、运行时与 Private 发布收口（2026-08-25）:

- G6 在一台 Sony G8441 API 28 arm64 物理设备、API 28 x86_64 AVD 与 API 25 x86 AVD 上执行 9/9 tests 和 9/9 structured receipts。最终 Gate invocation `1d978a79-4d08-41d8-a443-0115fb91cb59`、SHA-256 `24fc3e2b09182859e4405ab1d125efd2fefdced843f0f89bc106c70e60e32970`，关闭同签名跨 APK Binder、canonical PFD、真实 R8、五产物、verified cache、ART load、hostile input、busy/cancel、进程死亡/EOF、身份复验与 authenticated rebind；其历史边界保持 `jniLinked=false`、`remotePublished=false`。
- G7 append-only `local.5` Gate invocation `2efce169-b337-47e5-8814-b2aa152232a4`、SHA-256 `fe3df1fdce2b6ff675b41cad8d2da4720a6554da86230f11d1440f1d5f66953d`。随后 Sony API 28、API 25 x86 AVD 与 API 37 x86_64 16 KiB AVD 的 3/3 focused tests 和 3/3 Retrace executions 全通过，实际覆盖反射、运行期动态类名、Java serialization、脚本公开入口、shrinking、JNI 及 pinned R8 Retrace；runtime Gate invocation `36e7e2ff-b734-4034-96ab-cce5a0a037f5`、SHA-256 `263a80a840b93d73de31e727ce9a76a824e44f326f3ae99b22a6f64850a466ff`。
- R8 仓库的 4 个 reachable commits、注解标签 tagger 及本地 Git 身份均为 ID-based noreply。Private repository `SuperMonster003/AutoJs6-Plugin-R8-Compiler` 当前 `origin/master`/HEAD 为 `277ce8a05faa9566abcf474fcb0d3e6f928737ff`；注解标签对象 `fdce4dc42e6b1f65dae8677099d0f4b77fafec4a` 指向 `29abdf6a2742e3f327b17eb6ca1f50684bd5f72b`。G8 Private prerelease Gate invocation `ab010b7d-800f-43d9-acc9-27efb087efa2`、SHA-256 `ead4d551ae7eb13e319bc5ffed3639edc1ab96c6a85b9088ed7ca070f0a3e000`，冻结 5/5 assets 的长度与 SHA-256，并明确 `remoteVisibility=PRIVATE`、`publicPublished=false`。
- 本仓库新增只读 `scripts/r4-r8-closeout/`：12/12 mutation/self-close tests 全绿；真实 Gate invocation `eb04ee80-d25b-4d1d-85dc-b461abcba4f0`、SHA-256 `4edc797ceaa0aaee08d429f657320864c467fd23429ab9736a26a076f711d803`。它逐字节绑定 G2-G8 八份 Gate、G6/G7 prerequisite chain、R8 clean HEAD/origin、全部 reachable commit 身份、注解标签、5 个 local.5/remote asset、AutoJs6 integration commit `4a9718d63923834c9a99fd70e0cd58c898e138f6` 及 57 个未漂移宿主文件。`gh api` 仅只读复核 Private 仓库/branch/tag/release/digest；没有 fetch、push、release/visibility mutation、资产下载、签名材料读取、ADB 或设备任务。

R4.2-G0 本轮实现与证据（2026-08-13）:

- 生产语义: V1 的 `DexCompilerMode.DEBUG/RELEASE` 现在通过唯一、穷尽式 `toD8ExecutionMode()` 同时驱动 API 26+ 的 `D8Command` 与 API 24/25 的 D8 CLI；`RELEASE` 精确映射为 `CompilationMode.RELEASE` / `--release`，没有 `else` 或 R8 分支。PluginInfo 的 family 由 `DexCompilerFamily.D8` 派生，避免与 capability 漂移。Maven 坐标 `com.android.tools:r8`、Android `release` build type 与协议中的 `RELEASE` 是三个不同边界；前两者不构成 R8 provider 语义或执行证据。
- JVM 契约: `D8ProviderBoundaryTest` 现为 5 项，锁定 application/plugin/variant/provider/engine/action、family enum 仍仅 D8、协议 enum 仅 `JAR`/`PROGRAM|CLASSPATH`/`DEX_ZIP`、DEBUG/RELEASE、minApi 24-36、multi-dex、无外部 classpath/调用方 desugared 配置及 `NOT_CLAIMED`。最终 `:app:verifyR4R8Boundary --rerun-tasks` 带动当前组合源码 15 suites / 81 tests 全部通过；同一 114-task 总复核另重建默认 D8 8.13.22 矩阵 60/60（54 个真实成功、6 个预期失败）。历史 G0 报告继续只表示当时的 D8/R8 separation，后续 R8 证据不倒改其 false claims。
- 静态门禁: `scripts/r4-r8-boundary/` 固定 contract/schema 与 15 项仓库检查，绑定 Manifest 两个 service 的 exact allowlist、实际 Android applicationId、runtime/PluginInfo/engine/session dispatch、六个生产输入完整 SHA-256、DEX API AAR SHA-256、Kotlin/Java 生产 runner 与用户文档。mutation self-test 22/22 PASS，覆盖语义/身份/runner/dispatch/AAR/docs 漂移、损坏 contract/schema/module 的旧 PASS 原子替换，以及 direct、junction/symlink、hardlink、现存或未来生产源码的 OutputPath 覆盖拒绝。Gradle task graph 与显式 prepare task 都会在 JVM prerequisite 前把旧静态 Gate 原子改为 `passed=false`，所以 JVM/filter 失败不会保留旧阳性；最终组合源码再次带动 15 suites / 81 tests 全绿并通过 15/15 静态检查；生成多语言文档后的最终 Gate SHA-256 为 `c4015ef317857b6a7cad43944321241bfc06747f19f14bd5b47aa099f0332f03`，且报告不持久化 workspace/temp 绝对路径。
- Android 构建层: 完整组合复核先以 `--offline --no-daemon --rerun-tasks` 实际执行 114/114 tasks；随后生成多语言文档并再次执行 109/109 tasks，`:app:verifyR4R8Boundary :app:lintDebug :app:assembleDebug :app:assembleRelease` 全部成功。最终 lint 为 0 error / 8 warnings，当前 Debug APK 为 9,514,377 bytes、SHA-256 `9ba6e2c0cdf8716b1a344180cea43274ba74f21c77cd5c880a1631ce2d9f97ab`，Release APK 为 3,505,817 bytes、SHA-256 `bf545505ced0e55df2fa8ac8c832e56474ea12068fe3b038707fce99d496d810`。稳定 G0 证据包仍保留其冻结构建的 Debug/Release SHA-256 `30ad3b741c1c4ee28b3a0b8ff78479e0c03cec3559154bd390eb5fb35909a66d` / `e40c0375e4e6a5349ff0a0c244fab959c0bbd95ef2fc288992feb70b3d09673e`，不把 later workspace APK 冒充包内实物。Release APK 的 AGP/R8 minification 只属于本 D8 APK 的打包过程，不是 `R8Command`、规则、多产物或跨 APK R8 provider 验收。
- 稳定证据包: `D:\idea-projects\.bak\AutoJs6-DEX-R4-Evidence-20260813\r4.2-g0-d8-release-boundary-5a3921ea-d950-486b-9668-cffb231e4b36`；`report.json` SHA-256 为 `e497e8c0766355a2fed88a18288dd97e5c50399ea5ee644b62604cfe7748ba6f`。该包保留三条成功命令 transcript、R8 static gate、当前 D8 baseline gate 与 60 个 cell、15 份 JUnit XML、lint、Debug/Release APK、源码/脚本快照与 Git 状态；最终共 119 个 physical files，self-excluding manifest 覆盖 118 entries，path/hash/byteLength/unlisted diff 均为 0。
- 独立边界与证据级别: G0 盘点时未发现可复用的独立 R8 provider；既有 `dex-compiler-api` V1/V1.1 family 与校验均为 D8-only，不能通过扩 enum、复用 Action/AIDL 或把 `RELEASE` 改名来偷渡 R8。G1 随后新建 sibling 并只冻结 contract/AAR；G2 已按该要求落地独立 applicationId/component、R8 engine 与生产 envelope；G3 v3 补上默认关闭的 exact selection/protocol、宿主持有的真实 transaction/adoption runner 与隔离 cache，G3 v4 再接入 Developer options 用户选择、公开脚本入口及只读 R8 DEX load seam。G0 静态报告自身继续严格声明 `SOURCE_STATIC_ONLY`，并保持 `r8ProviderImplemented=false`、`jvmVerified=false`、`binderVerified=false`、`r8Executed=false`、`deviceVerified=false`；后来的 G1/G2/G3 证据不能倒改该历史报告。
- 设备边界: 本轮没有运行 ADB、`connected*`、安装、Binder/PFD、跨 APK、设备 R8 编译或设备任务，也没有触碰 `QV710AF65F`。G5 已关闭 append-only 本地签名发布历史，因此 R4.2 五个本地 aggregate 全部关闭；远端发布仍按所有者要求保持 false。设备/Binder 验收仍是 R4 总退出的独立缺口。

### R4.3 其他编译能力

- [x] Java/Kotlin 源码编译保持为独立插件或构建层，先输出经过验证的 JAR，再交给 DEX provider。
- [x] AAR 资源合并、APK 打包、签名和安装继续位于宿主构建/发布链，不进入本插件。

R4.3 本轮实现与证据（2026-08-25）:

- `scripts/r4-other-capabilities/` 固定 `STATIC_PRODUCTION_CAPABILITY_AND_BUILD_LAYER_SEPARATION` contract；生产面必须恰好是当前 20 个 Kotlin files，逐文件扫描 Java/Kotlin source compiler API/CLI、外部进程、AAPT/bundletool/apksigner/zipalign、AAR resource pipeline、keystore/apksig、PackageInstaller 与 ADB/ddmlib 九组禁用能力。当前 20/20 文件、9 组 pattern 均为零命中。
- 冻结 `dex-compiler-api.aar` 仍为 154,988 bytes、SHA-256 `4766af19ea414400177ba8541f753737c8bf40624cbfc866bb5442cc4b07fea5`；协议 enum 与新增 JVM 测试共同锁定唯一输入 `JAR`、输入角色 `PROGRAM/CLASSPATH`、唯一输出 `DEX_ZIP`。生产 materializer 必须将输入落成 `.jar`、执行 strict ZIP/JAR framing、SHA-256 与 class-entry 验证后，D8 才能接收 program/classpath；因此 `.java`/`.kt` source 必须先在独立插件或构建层产出经过验证的 JAR。
- Manifest 继续只有 `org.autojs.permission.PLUGIN`、三个既有 actions 与两个 services，不含安装权限/action。Gradle `com.android.application`、`signingConfigs`、`packaging`、`assembleRelease` 与 release copy marker 被明确分类为插件自身的构建/发布层；生产 runtime 不拥有 AAR resource merge、APK package/sign/install 能力，也没有对应 runtime dependency。
- mutation regression 13/13 PASS，覆盖新增/Java 生产源码、Java/Kotlin compiler、ProcessBuilder、AAR merger、PackageInstaller、JAR validation、manifest install permission、build signing marker、runtime compiler dependency、API AAR 篡改及损坏 contract 的旧 PASS 原子覆盖。最终 114-task 总复核中的 `:app:verifyR4OtherCapabilities` 带动 15 suites / 81 JVM tests 全绿；Gate invocation `8c4c911f-4482-4611-9e9f-76a35a2cca4a`、SHA-256 `b7dbe9717df7e7e98d3853ac24baad2d93e02248e8213726e478ab19934df9ec`。该 Gate 没有执行 source compilation、打包、签名、ADB 或安装。

#### R4 退出条件

- [x] 已将候选 D8 实际晋升为默认 pin，并在同一 source/build identity 下完成一次旧 pin rollback；单纯 candidate override 与撤销不计为 promotion/rollback。
- [x] R8/源码编译若落地，均拥有独立身份、安全模型、验收矩阵和发布证据；当前源码编译没有进入 DEX 插件，因此以 fail-closed absence/validated-JAR boundary 关闭本项，不虚构尚不存在的 source provider 发布。

## R5: 可用性、诊断与发布治理

目标: 在不改变 R0-R4 已验收语义（默认关闭、显式选择、单次同语义回退、取消不回退）的前提下，把"普通用户能看懂、能用好、能反馈"变成可验收面，并为下一个正式版本建立可复核的发布与评估节奏。

### R5.0 用户文档可读性重构

- [x] 重写 README 模板与全部 10 个 locale 的 JSON 源：以"是什么、怎么用、怎么排查"优先，新增"工作原理"、"常见问题"与"能力边界"章节，安装步骤改为编号清单，参考信息集中到"技术参考"；面向用户的文档不再出现 R 阶段编号、canonical 矩阵、single-flight 等内部验收术语（它们保留在本文件中）。
- [x] 重写全部 10 个 locale 的更新日志条目，用用户可理解的语言描述 v1.0.0 的行为与边界（默认关闭、手动启用、单次回退、权限模型）。
- [x] 生成器保持幂等：`.python/generate_markdown.py` 连续两次运行，第二次对 25 个生成文件零改动；`git diff --check` 无空白错误。
- [x] 生成产物人工核对：简体中文主 README 逐段核对章节顺序、代码块与列表渲染；其余 locale 由同一模板生成，结构一致。
- [x] 应用内 `plugin_instruction.md`（10 个 locale）与新 README 口径同步，覆盖默认关闭、手动启用与回退语义。
- [x] 邀请至少一名未参与开发的用户按新 README 完成"安装 → 启用 → 运行示例脚本"的完整走查，记录卡点并回填文档。

R5.0 本轮证据（2026-08-25）:

- 重写范围: `.readme/template_readme.md`、`.readme/lang_*.json` × 10、`.changelog/lang_*.json` × 10；`generate_markdown.py` 仅新增 `placeholder_boundaries` 列表渲染一处。
- 幂等验证: 生成器连续两次运行，25 个生成文件（README.md、`.readme/README-*.md` × 10、`app/src/main/assets/doc/CHANGELOG*.md` × 14）的 SHA-256 在复跑前后完全一致；`git diff --check` 退出码 0。
- 内容边界: 本轮只改文档源与生成器的一行渲染逻辑，未修改生产源码、未运行 Gradle/ADB/设备任务、未发布新版本；`version.properties` 保持 1.0.0/build 4。

R5.0 续推进证据（2026-08-26）:

- `app/src/main/res/raw*/plugin_instruction.md` 共 11 份资源文件，覆盖默认英文资源及 10 个 locale；默认资源与 `raw-en` 字节内容一致。各语言均按“启用前提 → 编号启用步骤 → 正常调用与回退 → 关闭/恢复 → 安全上限 → 问题反馈”组织，并明确安装不自动启用、至多一次同语义内置回退及取消不回退。
- README 的 10 个 locale 源已把阶段状态更新为“R5 进行中”，不把本地实现写成真机或发布完成；生成器再次连续运行两次，25 个生成文件第二次 SHA-256 零变化。
- R5.0 当时为 5/6；下述独立走查已补齐最后一项，当前为 6/6，本小节完成。

R5.0 独立走查与真实样例兼容性闭环证据（2026-08-26）:

- 独立走查: 未参与开发的测试者明确确认已按 README 完成“安装 → 启用 → 运行示例脚本”的完整流程，测试者身份与使用过程均无卡点，因此本轮没有需要回填的文档障碍；这关闭 R5.0 第 6 项及默认启用前置清单的“可用性”，不代表 R5.2 性能或 R5.3 发布完成。
- 真实输入: 测试者使用 Java-WebSocket 1.6.0 JAR；设备原件为 292,542 bytes、SHA-256 `7e5f73600c7d88f9cd28a63f7c0c9cd64efb5490601fa6f1a26963830cbba664`，共 91 entries / 87 classes，ZIP 完整性正常。EOCD 携带合法 5-byte binary archive comment `04 f7 41 04 00`。测试者最初观察到脚本 26.647 秒成功，但只读日志复核证明当次 provider 在 `INPUT_VALIDATION/INVALID_ARCHIVE` 后由宿主内置编译器回退成功，不能冒充插件成功。
- 插件修复: commit `cec2941e983f6fc406faee8518977779b053d2d6` 实施上述有界 EOCD/comment 兼容，并在 Release shrinker 中完整保留嵌入式 D8 engine 及其 `META-INF/services` provider。设备验证用非调试 Release APK 为 6,633,402 bytes、SHA-256 `e67123636ca649aaef0ec25da2033b714aa9adc62829d039ca87ea7146406e45`，保留 service provider `com.android.tools.r8.internal.xp1`，signer certificate SHA-256 为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`。
- 宿主根因与修复: D8 生成的 118,628-byte DEX ZIP（SHA-256 `c475d9daaee09995833c6ad35f7ea715297be30acb9f208d8c46127b0587bc7a`）含一个 118,508-byte `classes.dex`、DEX 039 与 87 个 class definitions，`7-Zip`/`dexdump` 均可完整解析。旧宿主错误要求 `class_idx` 单调递增，因而以 `INVALID_DEX_SECTION` 拒绝合法的依赖拓扑；[Android DEX 格式](https://source.android.com/docs/core/runtime/dex-format)要求本地 superclass/interface definition 先于引用者，而不是按 `class_idx` 排序。宿主 commit `959817a72b81b6f64556983aadaa2fb297742b20` 改为预扫描唯一 class indices，再验证本地 superclass/interface 的先行关系；同一捕获产物由旧 validator 拒绝、由新 validator 接受。
- 最终设备闭环: 在获授权的 `BH900ASK9E`（Sony G8441、API 28、arm64-v8a）安装 AutoJs6 6.8.0 build 5276 与上述非调试 Release 插件；两者 signer 一致且 opt-in/exact component 保持。清空进程后的真实脚本经插件编译、宿主复验并由 `DexClassLoader` 加载 `org.java_websocket.WebSocket`，设备验证包的脚本为 16.812 秒，日志无 `DEX compiler provider fallback`；宿主私有 cache 发布同一 118,628-byte verified ZIP。相同脚本随后为 0.364 秒，宿主与插件双进程冷启动后的脚本本体为 1.025 秒；冷命中只刷新索引访问时间，DEX ZIP 写入时间仍为首次发布的 16:09:56。更新 changelog/README 资产后又覆盖安装最终工作树 Release `9b1a9c1666d703ba82b33fcd6d1c3ca3de3a321ff815badac8554bb2648dfc9e`；provider 身份更新触发一次新的真实 D8 编译，脚本 17.029 秒成功且无 fallback/拒绝/崩溃，紧随其后的同包 cache hit 为 0.328 秒。当时的粗粒度轮询没有观测到 provider 进程；纠正后的 R5.2 正式采集证明进程冷启动 plugin cache hit 仍需 capability-bound 握手且 30/30 均观测到 provider，因此不再把该单次未观测结果表述为“未启动”。这些单样例时长只证明路由/缓存，不作为 R5.2 性能基准。
- 失败记录: Sony API 28 上首次使用 debuggable 插件进程时，ART 的 JDWP/CheckJNI 路径在 `ADB-JDWP Connec` 线程发生原生 SIGSEGV；当前 IDE 项目又不包含宿主源码，无法建立宿主 catch-point 调试会话。后续用同签名、`debuggable=false` 的 Release 隔离该环境问题，并以受控的一次性输出副本定位宿主 validator 根因；副本源码随即移除，设备副本也已删除。初始未完整保留 D8 的 minified Release 则稳定返回 `COMPILATION_FAILED`，据此补齐上述 keep 规则。最终拟验证包不含捕获代码，未把 Debug/JDWP 失败隐藏为成功。
- 本地门禁: 插件 `:app:testDebugUnitTest --rerun-tasks` 为 15 suites / 90 tests，failure/error/skipped 均为 0；Debug lint 为 0 error / 27 warning，Debug 与 Release assemble 均成功。生成更新后的 changelog/README 资产后，最终工作树 Debug APK 为 9,548,924 bytes / SHA-256 `6fac47cd25d8517fab06bdd8f37a19b8a47dbfe4f2ea8f13e883486426b2ac98`，Release APK 为 6,636,134 bytes / `9b1a9c1666d703ba82b33fcd6d1c3ca3de3a321ff815badac8554bb2648dfc9e`，Release 仍为 `debuggable=false`、保留 `com.android.tools.r8.internal.xp1` 且 signer 不变；它与设备验证包的字节差异只来自随后生成的文档资产，运行时代码与 shrinker 规则未变。隔离宿主 worktree 的 DEX 全命名空间加 R8 DEX ZIP validator 回归为 20 suites / 187 tests 全绿，`:app:assembleAppDebug` 成功；安装的 arm64-v8a 宿主 APK 为 42,401,145 bytes、SHA-256 `375ace8c991454ec7c113d08c9d46693356c5e0898b39d8c1613437d1c26c979`。

### R5.1 诊断与可观测性增强

- [x] 采集完整 D8 info/warning 诊断流（R2 遗留的非门禁增强），在既有 64 KiB 诊断预算内分级截断与脱敏。
- [x] 以旧 reader 可安全跳过的 optional tags 扩展 wire schema，携带失败 origin/entry/位置元数据，不改变 V1.0/V1.1 既有字节语义与 AIDL。
- [x] 宿主开发者选项提供"最近一次 loadJar 编译走了哪条路径（插件 / 内置回退 / 缓存命中）"的可读摘要，仅存进程内存，不持久化路径、摘要值等敏感信息。
- [x] 为 BUSY、超时与回退各提供一条用户可读的提示文案，覆盖 10 个 locale。

最小证据: 协议/插件/宿主 JVM 定向测试，加一个获授权 Android 目标上的真实失败诊断用例；不要求重跑多 API/ABI 设备矩阵。

R5.1 本地实现证据（2026-08-26）:

- 协议: `DexCompilerDiagnostic` 的既有 required tags 1-3 保持不变，新增 optional tags 4-6（逻辑 origin、canonical archive entry、嵌套位置）；冻结旧 reader 测试可跳过新 tags，V1.0/V1.1 AIDL 与版本号未改。协议模块 5 suites / 44 tests 全通过。
- 插件: API 26+ `D8Command` 与 API 24/25 CLI-compatible 参数路径均把 INFO/WARNING/ERROR 回调交给同一 collector；错误可逐出 warning/info，warning 可逐出 info，count 与 byte ceiling 共用 64 KiB 预算。私有工作区路径映射为 `program`、`classpath:n`、`runtime-library:n`、`output` 或 `<redacted-path>`，公共 collector 路径不调用 API 26 `java.nio.file.Path`。插件 15 suites / 86 tests 全通过；Debug lint 为 0 error / 27 warning，本阶段不把 warning=0 冒充为完成条件。
- 宿主: 请求级诊断预算包含 code/message/origin/entry/位置的全部保留字节；最近路由只在最终 classloader 采用成功后写入独立的 `AtomicReference`，取消与加载失败不会生成虚假的成功路径。R2 的最近 provider 失败仍由共享 producer 写入另一份进程内快照，不会被后续路线更新或非远端回退覆盖。开发者选项显示本地化路径/提示及有界稳定失败枚举、计数与 code 摘要；它不显示 request id、文件路径、输入输出摘要、原始 provider message 或时间戳。3 个新增/关键定向 suites / 72 tests 全通过，随后 `org.autojs.autojs.core.plugin.dex.*` 全命名空间回归为 19 suites / 180 tests 全通过。
- 配对 AAR: `libs/dex-compiler-api.aar` 为 163,690 bytes，SHA-256 `6beea0450017956ec9a5469083142529dc5f893c4e6450848a8a9dd5e1526b7c`；R4.3 责任边界 mutation 自测 13/13，并由 `:app:verifyR4OtherCapabilities` 产出 PASS invocation `e40c07af-3f5f-4150-ad12-cb4a2d171c34`，继续锁定唯一 `JAR` 输入、`PROGRAM/CLASSPATH` 角色与 `DEX_ZIP` 输出。
- 当轮边界: 上述本地实现提交当轮未运行 ADB、`connected*`、安装或设备任务；后续设备闭环单独留证，不倒改该历史事实。

R5.1 设备闭环证据（2026-08-26）:

- 配对产物: x86 宿主 APK 为 46,177,867 bytes / SHA-256 `a07e69e20f9a14fafe1c35c1db03604b3103f5a5f4b9894c2b88f5cf666dba69`，arm64-v8a 宿主 APK 为 46,219,429 bytes / `fca09ff81ba528d7f1b45803a0e1ee38a484ef779c6b008ae20790aa70a05b2c`，androidTest APK 为 1,852,928 bytes / `327cc8c5c97f90fde92c2c7a8188e67c4e45d63114785f59aed13f371b47af57`，插件 Debug APK 为 11,009,748 bytes / `1cf2b74de1ab9ae387171a31073830872c0ac4c693f349a40e403d4d7d1c782b`；四者 V2 signer certificate SHA-256 均为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`。
- 真实失败/恢复: `DexCompilerRealProviderAndroidTest#realProviderFailureCarriesR5DiagnosticsAndNextProductionLoadRecordsRoute` 分别在 `AVD_API_24`（API 24/x86）、`AVD_API_25`（API 25/x86）和首选物理机 `QV710AF65F`（Sony XQ-AT72，API 31/arm64-v8a）执行；三格均为 `OK (1 test)`、0 skipped、`INSTRUMENTATION_STATUS_CODE: 0`。API 24/25 覆盖 CLI-compatible D8 回调路径，API 31 覆盖 `D8Command` 路径。
- 诊断断言: 三格均得到 1 条 ERROR、117 retained bytes、origin=`program`、entry=`org/autojs/fixture/dexcompiler/Broken.class`，消息不含输入绝对路径、Android 私有路径或控制字符；失败不会伪造成功路线，随后生产 `AndroidClassLoader` 加载返回 42、记录 `route=PLUGIN` 且重复请求命中 exact cache。该 malformed fixture 没有产生位置，`positions=0` 不冒充位置型 D8 回调；位置 optional tag 仍由 JVM codec/provider 测试覆盖。
- 取消与 BUSY: 同一首选真机上的真实 lifecycle 用例单独通过，锁定 blocked session 的单一 retryable `BUSY/QUEUE` 终态、取消终态、EOF、gate 释放与会话复用；生产加载器取消用例也以独立 `OK (1 test)` 通过，确认只到达 decision boundary 一次且不会启动内置编译器回退。用户可见提示映射继续由 R5.1 宿主 JVM 本地化测试覆盖。
- 清理与边界: 每个接受结果之后均确认宿主、androidTest、插件包 `PACKAGES_ABSENT=3/3`；两个 AVD 已关闭且未保存快照；真机 user 0/10 拓扑前后一致。详细报告在 AutoJs6 `docs/dev/dex-compiler-r5-diagnostic-device-evidence-2026-08-26.md`，宿主门禁提交为 `2d9192716620bc4aa0c19462f22d224db2886f77`。这关闭 R5.1 的 4/4 实现与最小设备证据，但不替代 R5.3 V1.1 classpath 矩阵、性能基准或拟发布配对验收。

### R5.2 性能基准与晋升评估

- [x] 建立可重复的本地基准: 固定语料下对比插件路径与宿主内置编译器的耗时、内存与缓存命中率，产出机器可读报告并记录环境（JDK、设备/模拟器、语料摘要）。
- [x] 基于基准数据定义"性能晋级"的数字门槛；达标并留证前，用户文档不得声明性能优势（当前 README 已明确"目标不是性能"）。当前候选已由机器门禁判定为 `NOT_PROMOTED`，该失败结论本身不阻塞门槛定义条目的完成。
- [x] 建立默认启用（opt-out）的前置条件清单（稳定性、诊断覆盖、矩阵覆盖、回退演练、回滚路径），并逐项挂接证据目标；清单闭环前路由保持默认关闭。

默认启用前置条件清单（建立于 2026-08-26，当前 3/7）:

- [x] 诊断覆盖: R5.1 的获授权 Android 真实失败/恢复用例已在 API 24/25 x86 AVD 与 API 31 arm64 真机通过；设备断言覆盖脱敏与预算，当前构建的独立真机门禁覆盖 BUSY、取消终态与取消不回退，用户可见提示映射由宿主 JVM 本地化测试覆盖。
- [ ] 性能与资源: 纠正后的 R5.2 固定语料报告覆盖插件/内置/缓存路径；冷时延 3/3、联合 P95 PSS 6/6、缓存状态 6/6 和确定输出 6/6 通过，但进程冷启动 cache-hit added P95 时延 0/3 通过。三档分别增加 232.7 / 229.2 / 268.4 ms，均超过 100 ms 上限，因此保持未勾选。
- [ ] 矩阵覆盖: R5.3 至少 3 个代表格通过，包含一台获授权 arm64 真机及 API 24/25 CLI-compatible 路径。
- [ ] 回退演练: 用拟发布宿主/插件配对验证 BUSY、超时、远端失败、无效输出、采用失败与取消，且每项满足至多一次同语义回退或取消不回退。
- [x] 回滚路径: README 与 10 个 locale 的应用内说明均记录“选择 Built-in D8/dx 并重启 AutoJs6”，无需卸载宿主或清除数据。
- [x] 可用性: 一名未参与开发的测试者已完成 R5.0 的安装、启用与示例脚本完整走查，并明确确认测试者身份与流程均无卡点；真实 `java-websocket.jar` 样例随后触发并闭环了受控 JAR comment、Release D8 保留及宿主 DEX topology 三项兼容修复。
- [ ] 发布治理: R5.3 固定拟发布版本、配对宿主 build 与 APK/AAR 摘要，并完成发布前回归和可复核证据包。

该清单的“建立”不代表默认启用获批；未勾选项存在期间，安装后默认关闭和显式选择语义保持不变。

R5.2 基准与晋升评估证据（2026-08-27）:

- 实现与纠错: AutoJs6 commit `2a808a29953af5c3fe77e522f54f5c87aed7d0f9` 建立固定语料夹具、显式设备/配对 APK 采集器与独立数字门禁；`65c69a95f97dda32a4e8f63640097bd9699d74a9` 增加三次连续 PID 缺席的进程静默门禁；`0049a2a63ac2fa5a3e8ccb9d4f76db69536d2aab` 修正内置 cache-hit 证明。原夹具每次新建生产 `AndroidClassLoader` 时会清空预热目录并重新编译，同名/同大小/同 SHA 断言无法识别确定性重编译；API 33 第 91 个样本的 30,152→30,176 bytes 漂移暴露了该问题。生产双参数构造器语义不变，仅模块内 benchmark seam 在内置命中格保留预热缓存，并强制产物名称/大小/SHA/mtime 全不变；强化评估器会拒绝旧报告。
- 固定语料与契约: on-device Java 8 classfile generator V1 对 `java8-1x8`、`java8-128x8`、`java8-2048x8` 双次生成并要求逐字节一致；输入分别为 742 / 93,334 / 1,474,582 bytes，声明方法数 9 / 1,152 / 18,432。每格 2 warmup + 10 measured，样本前强停宿主/provider 并要求进程静默，计时从 `runtime.loadJar` 至真实 `DexClassLoader` 类解析和静态调用返回 42。进程冷启动 plugin cache hit 因最终 semantic key 依赖已认证 capabilities，仍要求观测 provider 进程。
- 优化与配对产物: 插件 commit `ca4c1cc421f4388f773d1391c65aec8d21793dfb` 将 API 26+ command 与 API 24/25 CLI-compatible D8 内部并行度限制为 2；15 suites / 90 tests、lint 0 error / 27 warnings、Debug/Release 构建全绿。纠正后的配对为宿主 x86_64 43,221,999 bytes / `5051a55d1a9136032e20ba84d4584f75a2a1f4e5b1d267a4a936face3c6780ca`，androidTest 1,711,930 bytes / `fa6be30475620b50aadba51af0782e9a86142856f89f3db3e6490ae8c81b12f7`，非调试插件 Release 6,638,094 bytes / `3b9418227d90fccac495519f61552a78ef8ece5946602930a9100f7ba77981ad`；三者 signer 均为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`。
- 纠正后正式结果: campaign `4acd2687-e372-4f9f-8428-265a2c34dd86` 在获授权 `AVD_API_33`（API 33/x86_64）完成 144/144 timed、120 measured，cleanup/restoration error 0，三包前后均不存在，AVD 随后以 no-snapshot-save 关闭。120/120 route/cache、30/30 内置命中 mtime 零增量、30/30 插件 `CACHE_HIT` 和 12/12 确定输出均通过；冷时延 3/3、联合 P95 PSS 6/6 通过，大语料冷路径为插件 252,208 KiB 对内置 346,865 KiB（-27.29%）。但 cache-hit added P95 三档分别 +232.7 / +229.2 / +268.4 ms，均超过 100 ms，机器门禁仍为 `NOT_PROMOTED`。
- 证据与恢复: AutoJs6 稳定证据 `docs/dev/dex-compiler-r5-performance-evidence-2026-08-27.md` 保留原始真机报告、所有部分失败/阻塞报告及纠正结论；当前原始 JSON 为 465,147 bytes / `8a11f2cb2568a2500976d7bd89fa32af9ff674c48e58332a5ccda8f9cb17a645`，评估 JSON 为 10,135 bytes / `2332dea508750806341fd45d1fc615357b6a75348ff1c14e845f518ea7748cc9`。首选 `QV710AF65F` 两次正式优化复跑分别在 2/144 与 94/144 因 USB 断连阻塞；设备仍不在线，两个 run-owned recovery snapshots 保留，重连后须按证据恢复并验证原宿主 SHA `fca09ff81ba528d7f1b45803a0e1ee38a484ef779c6b008ae20790aa70a05b2c`。因此默认启用清单的“性能与资源”仍未完成，README 继续明确目标不是性能。

### R5.3 V1.1 矩阵扩面与发布节奏

- [x] 将 V1.1 classpath 验收从单一 API 34/x86_64 纵切扩展到 R1 七格矩阵中至少 3 个代表格，至少含一台获授权 arm64 真机；沿用 R1 的证据与设备授权规则。
- [x] 发布携带 D8 8.13.22 默认 pin 的下一个正式版本（建议 v1.1.0），更新 `version.properties`、changelog 与 `releases/`，并记录配对宿主构建号与 APK 摘要。
- [x] 确定性调查: 在两台机器或两个干净目录对同一输入重复编译并记录字节差异；得到可复核证据前，`determinismClaim` 保持 `NOT_CLAIMED`。

本轮闭环证据（2026-08-27）:

- classpath 最终发布配对: host commit `b276708646b127e64b7f43af4ede94839004d0c9`、plugin release-source commit `e5804757d926d45db219fc2eb4b2b128714b4160`。正式 campaign `d9b97e77-84ad-41dd-a0f2-a8e08eef3fea` 在 `AVD_API_24` API 24/x86、`DEX_R1_API34_X64` API 34/x86_64 与获授权物理设备 `968e9f18` API 35/arm64-v8a 三格均为 exactly-one instrumentation PASS；覆盖公开 Rhino V1.1 入口、真实 provider、ordered compile-only classpath、最终 `DexClassLoader`、V1.1 cache hit 及独立 V1.0 回归。三格分别记录 57/57/56 条 exact-serial 命令，四个范围包 pre/post 均 absent，cleanup failure 0；API 34 AVD 以 no-snapshot-save 启停。聚合 Gate 为 2,378 bytes / `e2f8c722e2c539e08dd119b39d56af7a2d79581c32c3f50136939ebe43e03a24`，宿主稳定证据为 `docs/dev/dex-compiler-r5-classpath-matrix-evidence-2026-08-27.md`（host commit `1c5bee578`）。这是三格代表性扩面，不冒充 R1 canonical 七格重跑；首选 `QV710AF65F` 当时仍未在线。
- v1.1.0 发布材料与门禁: `version.properties` 已更新为 `VERSION_NAME=1.1.0`、`VERSION_BUILD=5`，10 locale changelog 与全部生成文件同步；D8/R8 默认 pin 为 8.13.22。强制离线执行 `:app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleRelease --rerun-tasks` 为 15 suites / 90 tests、failure/error/skipped 0，lint 0 error / 18 warnings，Debug/Release 均成功。非调试 Release 为 6,642,158 bytes / `a8fe8b64723c0bae58c94a3129ce58043ea2cb2ef5a8b168b0a861f8d11b9205`，v2 signer certificate 为 `31a681fcfffb3e428420cae280ded89292b12a3b0f59e19b7a73e32a8ae4c213`，D8 service provider `com.android.tools.r8.internal.xp1` 保留；append-only 本地发布副本为 `releases/autojs6-plugin-dex-compiler-v1.1.0-c569dbbe.apk`。正式配对宿主为 AutoJs6 6.8.0 build 5276：host universal 43,975,067 bytes / `24f4ee855174b994d9e37472b48120b2059cc82f3e64507c447799b95dfcaa8f`，androidTest 1,508,760 bytes / `2b82aabf644cc1c2cc2983faf902d57ca93975bfb59197245fca9e34eea2fdcb`，三包 signer 一致。
- 双净目录调查: 在同一机器的两个独立 detached clean worktree 对 commit `e5804757d926d45db219fc2eb4b2b128714b4160` 分别强制离线执行完整 `:app:verifyR4D8UpgradeMatrix`，producer `66a4f739-ab20-42f4-8db8-5107db033bca` 与 `f3d7cc29-6bcc-4d8c-8011-d4baab52ab2e` 均为 pinned D8 8.13.22、60/60 PASS，Gate SHA-256 分别为 `61066541ad6c6981768083bd147c3b323888faad945464f221cb6735055477e1` 与 `f5e49be819813d3cafc22b4ebc8655cb95da29acb1c4fd3e3b9a5ad6e91475e8`。commit `226c5bf` 的比较器重新验证两套 Gate 后记录：60 格 input/runtime/outcome/status/topology 差异均为 0；54 个产出格的跨目录 output digest、逐 DEX manifest 差异均为 0，且各目录内部双次摘要一致；6 个预期失败格在两侧均无输出。比较报告为 30,752 bytes / `2fa8fdb387782fec76b912ff26b6a1573a3c65f13f2d7f024c0212dfd90bb148`；两套 Gate、120 份 cell report、实际 matrix/schema 与比较器已冻结到 `D:\idea-projects\.bak\AutoJs6-DEX-R5-Evidence-20260827\determinism-e580475`，132-entry 自排除 manifest 为 24,947 bytes / `1295a6cdde898c52f4d4dc79fa97683e92a0de6b9ac4761ad17c4544a3191b70`。证据边界固定为单机/双净目录/JVM compiler only，`determinismClaim=NOT_CLAIMED`，不外推到跨机器、文件系统、JDK 或未来编译器。

### R5.4 R8 provider 公开化协同（跨仓库；公开范围已移出当前 R5）

- [ ] 独立 R8 provider 完成从 Private 到 Public 的转换 Gate（含公开文档与配对宿主说明）。**已移出当前 R5**；原因是 owner 明确要求 R8 仓库及配对宿主继续保持 Private，去向为独立 R8 Roadmap 的 G9 Public Gate，未获新的公开授权前不得勾选。
- [ ] Public 转换完成后，本仓库 README 的"常见问题"与"能力边界"增补指向可公开访问的 R8 provider，并保持"D8 = 编译，R8 = 压缩/混淆"的分工口径。**已移出当前 R5**；去向同为 R8 G9 的公开发布后联动，当前 Private URL 不写入公开 README。

2026-08-27 写入前预检（历史状态）: GitHub API 返回 `SuperMonster003/AutoJs6-Plugin-R8-Compiler` 为 `PRIVATE`，远端 `master` 为 `277ce8a05faa9566abcf474fcb0d3e6f928737ff`，`v0.1.0-provider-dev-private.1` 当时为非草稿 prerelease；独立仓库的 G9 Public checklist 仍为 0/5。公开 AutoJs6 最新 Release 当时仍为 v6.7.0（2026-03-14），没有与 R8 验证配对的 AutoJs6 6.8.0 build 5276 公开产物；`SuperMonster003/AutoJs6-Official-Plugins-Index` 已是 Public，但在 provider 与配对宿主公开前不能完成注册。该预检没有执行远端写入，随后仅按 owner 新授权执行下述私有 Release 转换。

Owner 授权与范围裁决（2026-08-27）: R8 仓库继续保持 Private；允许创建正式 Release，但不得公开；AutoJs6 build 5276 / 配对宿主继续保持 Private；官方插件索引不得手动干预，等待其未来自动定时更新；R8 本地领先提交暂时保留且不推送、不改写，并发工作树修改也保持原样、不提交、不回滚。基于该边界，现有 Release ID `376144423` / tag `v0.1.0-provider-dev-private.1` 只以单字段 `prerelease=false` 从 Private prerelease 转为 Private non-prerelease；没有新建或移动 tag，没有修改 Release 标题、说明、目标分支、创建/发布时间或资产，也没有改变仓库可见性。

私有正式 Release 证据: campaign `eafd95f0-c8a1-4feb-8cfc-fb4ee8eba18c` 独立回读确认仓库前后均为 `private=true / visibility=private`，目标 Release 前后均为 `draft=false` 且转换后为私有仓库的 latest non-prerelease。5/5 资产的 ID、名称、大小、GitHub `sha256:` digest 与重新下载文件 SHA-256 前后一致，远端 branch/tag 三个真实 refs 不变；未认证访问仓库页面、Release 页面和 repository API 均为 HTTP 404。R8 本地 HEAD `3ba7304d2e565775d8cb072e388cabfa2c9a10d7` 继续领先 `origin/master` 1 个提交且未推送；采集期间出现的并发工作树修改保持原样。本次没有发布 build 5276、没有写官方索引、没有 Public publication。证据根目录为 `D:\idea-projects\.bak\AutoJs6-R8-Private-Release-Evidence-20260827\private-stable-release-eafd95f0-c8a1-4feb-8cfc-fb4ee8eba18c`；before/post manifest SHA-256 分别为 `f465dd94e5962f77c54652706137fba49285d7d7791b47d5d552eb5b530666fc` / `ada00f4814a97fbeec9233499a677ef2c2447d2f8ca1fa73322fa9184e512bb6`，1,843-byte receipt 为 `a866303f7435f121aa5e3287e3b35edfede47043ee62c09656a5cc7d95baf386`，26-entry 自排除根 manifest 为 4,914 bytes / `c536160e7ee36f21f34aa5c25cc7b77fb545ed339623ea590498472459878561`，全量重哈希 26/26 通过。

移出决定: 当前 R5 对跨仓库协同的职责已完成到“记录 owner 决策、完成获授权的 Private 正式 Release、固化证据并明确后续去向”。Public 仓库转换、配对宿主公开发布、公开 README 链接与索引可见性仍均为未完成，不得由上述私有 Release 证据冒充；它们整体移交未来独立 R8 G9 Public Gate，待 owner 重新授权公开范围后再独立验收。因此 R5 可依据“全部完成，或明确记录移出原因与去向”的退出规则关闭。

#### R5 退出条件

- [x] R5.0-R5.3 全部完成；R5.4 的 Private 正式 Release 已完成，未获授权的 Public 仓库/宿主/README/索引范围已记录移出原因并整体移交未来独立 R8 G9 Public Gate。
- [x] README 10 个 locale 与本路线图的阶段状态描述一致，生成器幂等检查保持通过。

## 阶段证据记录

完成一个阶段时，在这里追加一条简短记录；详细日志应保存在对应仓库的稳定路径中。

| 阶段 | 日期 | Commit | 结果 | 证据 |
|---|---|---|---|---|
| R0 | 2026-08-10 | 未提交 | 已完成 | 强制重跑 43 tests / 10 suites 全通过；large evidence 为 sourceBytes=66,595,045、providerLimit=67,108,864、maxHeap=62,914,560；同轮 lint 与 Debug/Release 构建均通过；仅属 JVM/本地验收 |
| R1 | 2026-08-11 | host `e39023758e3a66a24f0ce90466b5bc77a503515d`; plugin `1f50d5333ab3a58c4c0f00fe06a20a5692aa3448` | 已完成 | R1.1 生产加载链路 7/7、R1.2 自动化 4/4、R1.3 canonical 真实 provider Gate 7/7、退出条件 3/3；campaign `f3c2b1af-be93-41e7-b541-f167f90e5cc1` |
| R2 | 2026-08-11 | plugin `6e716af`; host `e65bef44d` | 已完成（交付 4/4，退出 1/1） | plugin 65/65、host DEX 166/166、lint 0 error；API 34 canonical closeout 三类真实 provider 场景全部 PASS，52 commands / 61 hashed files，pre/post clean；run `dab3f857-650d-4107-a3b9-941a1f7e02c2` |
| R3 | 2026-08-11 | host `c0b833a54`, `4d2b7dfed`, `a540e0f90`, `2e439a973`; plugin `ab08f08`, `8ebd7ff`, `e0f9470` | 已完成（交付 4/4，退出 1/1） | V1.0/V1.1 contract、provider bundle、同语义 D8-only fallback 与显式 Rhino 入口已通过正式门禁；run `fa6c21a7-7dda-4bee-9485-bf78906ed83c` 在单 API 34/x86_64 真实 provider 场景 PASS，非设备矩阵 |
| R4 | 2026-08-25 | DEX 本地收口提交；host integration `4a9718d63923834c9a99fd70e0cd58c898e138f6`；R8 `277ce8a05faa9566abcf474fcb0d3e6f928737ff` | 已完成（R4.1 4/4，R4.2 5/5，R4.3 2/2，退出 2/2） | D8 v2/v3 promotion→rollback→re-promotion 三套 60/60；R8 G2-G8 独立 identity/contract/host/Binder-PFD/device/ART-JNI-Retrace/local.5/Private prerelease 完整闭环；R4.3 20-source static Gate、13/13 mutation、15 suites / 81 JVM tests 全绿；DEX 仅本地提交且不推送 |
| R5.0 | 2026-08-26 | host `959817a72b81b6f64556983aadaa2fb297742b20`; plugin `cec2941e983f6fc406faee8518977779b053d2d6`; docs 本提交 | 已完成（6/6） | 独立测试者完整走通 README 且无卡点；真实 Java-WebSocket 1.6.0 样例闭环标准 JAR comment、Release D8 service 保留及宿主合法 class_defs 依赖拓扑；Sony API 28 arm64 最终插件路由与持久 cache 命中均无 fallback |
| R5.1 | 2026-08-26 | host implementation `4e58791238427c309ae5d4bbad07b9bc9d2a23d4`; host device gate `2d9192716620bc4aa0c19462f22d224db2886f77`; plugin implementation `4d08a612ae1d87059c28de98a66b8d3020763ac9` | 已完成（实现 4/4，最小设备证据 1/1） | 协议 44、插件 86、宿主 DEX 180 项本地测试全绿；API 24/25 x86 AVD 与 API 31 arm64 真机的真实失败/恢复 3/3 PASS，真机 BUSY/取消及取消不回退补充门禁 PASS；每轮配对签名一致并完成 3/3 包清理 |
| R5.2 | 2026-08-27 | host baseline `2a808a299`, quiescence `65c69a95f`, cache correction/evidence `0049a2a63`; plugin optimization `ca4c1cc` | 已完成（3/3；候选未晋级） | 纠正后 API 33/x86_64 正式 144/144、cache/route 120/120；冷时延 3/3、联合 PSS 6/6、cache 6/6、输出 6/6，通过；process-cold cache-hit added P95 0/3（+232.7/+229.2/+268.4 ms > 100 ms），机器门禁 `NOT_PROMOTED`，默认启用前置仍为 3/7 |
| R5.3 | 2026-08-27 | host matrix `b27670864`, evidence `1c5bee578`; plugin runner `563a9c3`, release `e580475`, comparison `226c5bf` | 已完成（3/3） | v1.1.0/D8 8.13.22 Release 与 AutoJs6 build 5276 配对；最终 campaign `d9b97e77-84ad-41dd-a0f2-a8e08eef3fea` 的 API 24 x86、API 34 x86_64、API 35 arm64 三格 real-provider classpath Gate 全通过且 pre/post clean；双净目录 60/60 + 60/60，54 个产出格跨目录摘要差异 0，仍保持 `determinismClaim=NOT_CLAIMED` |
| R5.4 / R5 退出 | 2026-08-27 | R8 private Release ID `376144423`; DEX docs 本提交 | R5 已完成（R5.4 Public 范围移交 R8 G9；退出 2/2） | campaign `eafd95f0-c8a1-4feb-8cfc-fb4ee8eba18c` 将既有 R8 Private prerelease 单字段转换为仍属 Private 的 non-prerelease；5/5 资产与 refs 不变，未认证 3/3 HTTP 404，26/26 证据文件重哈希通过。build 5276 未公开、索引未写、R8 本地领先提交未推送；Public Gate 明确未完成且不由本条冒充 |
