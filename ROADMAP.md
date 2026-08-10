# DEX Compiler Roadmap

更新日期: 2026-08-09

本路线图把后续工作拆成可独立验收的 R0-R4。每个复选框只表示对应条目已经有可复核证据，不能用较低层级的测试替代较高层级的验收。例如，JVM 单元测试通过不等于跨 APK Binder 或真实设备加载已经通过。

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
| R1 | 进行中 | AutoJs6 显式 opt-in 接入与真实 provider 设备矩阵 | AutoJs6 + 本插件 |
| R2 | 待开始 | 结构化诊断、取消/超时语义和进程恢复 | AutoJs6 + 本插件 |
| R3 | 待开始 | 协议 V2 的受控依赖输入、宿主规范化和多输入缓存扩展 | 协议 + AutoJs6 + 本插件 |
| R4 | 待开始 | D8 升级治理，以及与 R8/源码编译能力的清晰分离 | 本插件 + 独立 provider |

依赖顺序:

```text
R0 ──> R1 ──> R2 ──> R3
                    └──> R4
```

R4 的设计工作可以提前开展，但不得在 R0-R3 的接口中偷偷引入 shrinking、obfuscation 或源码编译语义。

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
- [x] EOCD、中央目录、本地文件头、extra field 和 data descriptor 的检查保持严格，不放宽 ZIP64、多磁盘、加密、注释、前置/尾随数据或未知压缩方法限制。
- [x] entry 内容仍以固定大小缓冲区流式解压，并继续执行单项、累计、class 总量、class magic 和压缩比限制。
- [x] 保留输入复制阶段的大小与 SHA-256 同步核验，失败时删除未完成的私有临时文件。
- [x] 正常 JAR 的 `ValidatedJar` 统计结果与改造前保持一致。
- [x] 对恶意长度、截断文件和不可读文件只返回有界、类型明确的失败，不泄漏运行时异常或产生无限循环。

### R0.2 对抗性与边界测试

- [x] 正向语料覆盖 STORED、DEFLATED、带/不带签名的 data descriptor、目录 entry、多个 class 和非 class 资源。
- [x] 覆盖恰好等于及超过压缩大小、entry 数、解压总量、单 class、class 总量和压缩比上限的边界。
- [x] 覆盖 EOCD 缺失/注释、前置/尾随字节、中央目录截断、entry 数或目录大小不一致。
- [x] 覆盖本地头与中央目录之间的名称、flags、method、CRC、压缩大小和解压大小不一致。
- [x] 覆盖 ZIP64 sentinel/extra field、多磁盘、加密、不支持的压缩方法、记录间空洞、重叠和乱序 offset。
- [x] 覆盖空名称、绝对路径、`..`、反斜杠、冒号、NUL、非 NFC、重复名称和非规范目录结尾。
- [x] 覆盖无 `.class`、伪 `.CLASS`、class magic 错误、目录携带数据和压缩炸弹。
- [x] 增加固定 seed 的 mutation/fuzz 回归；任一变体都必须在限定时间和内存内接受或返回协议化失败，不得 crash、hang 或 OOM。
- [x] 至少使用一个接近输入上限的大型稀疏/生成语料证明验证路径不创建与整个 JAR 等大的额外堆数组。

R0.2 的代表性回归切片:

- [x] 接受 STORED JAR，以及带签名 data descriptor 的 DEFLATED JAR，并核对 `ValidatedJar` 统计。
- [x] 拒绝本地文件头、中央目录和 EOCD 的固定截断变体。
- [x] 拒绝 archive comment、前置数据和尾随数据。
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

宿主工作树已经落地 R1.1 source wiring，并完成静态代码审阅、当前修正版代码/APK Gradle 门禁及 API 31 arm64 真实插件定向方法。宿主 DEX 定向门禁 16 suites/149 tests 全通过，Android test Kotlin 及 host/test APK 均成功 assemble；production concurrency、真实 lifecycle 与真实 corpus 共 7 个方法逐项通过。以下七项仍保持 0/7 未勾，因为 R1.2 的定向自动化证据尚未覆盖 R1.1 各条生产链路所要求的完整 failure、回滚、身份、回退与兼容性门禁，也不能替代 R1.3 设备矩阵。

R1.1 最初落地时的验证后发布只作为一次性 classloader handoff。该描述是 R1.1 当时的历史边界，不再代表当前工作树；后续 R1.2 源码部署已将其升级为有界的持久语义 cache。R1.1 七项仍须由当前主源码门禁及更高层级证据确认后才能勾选。

- [ ] 实施中: 宿主固定 raw JAR 输入快照，先计算大小和 SHA-256 再打开 session；若远端失败需要本地回退，只能复用同一份已保留快照。
- [ ] 实施中: 只通过用户显式选择且与宿主完整 signer 集一致的 exact component 建立 Binder 会话；跨进程只传文件描述符，不向插件暴露路径。
- [ ] 实施中: 固定 provider 身份并完成 Binder 握手后才最终化协议版本和 runtime library fingerprint；capability 与 ceiling 只用于验证或拒绝，不重写请求。
- [ ] 实施中: 宿主用完整 `DexIndexedZipValidator` 独立复验输出大小、双重摘要、DEX header、命名连续性和条目边界。
- [ ] 实施中: 验证产物仅能经宿主持有的复制、复核与原子发布进入 cache；失败、取消、超时、Binder death 或进程死亡使事务失效，不留下可加载半成品。
- [ ] 实施中: 只有 raw `runtime.loadJar()` JAR 可把宿主已验证的 DEX ZIP 交给 `AndroidClassLoader`；AAR、`loadDex()`、`defineClass()` 与兼容辅助路径继续使用内置实现。
- [ ] 实施中: 实验默认关闭；provider 未启用、不可用、远端失败、输出拒绝或 verified ZIP 接管失败时至多执行一次内置 D8/dx 回退，用户取消作为中断传播且不切换编译器。

### R1.2 自动化测试

R1.2 的四项精确定义均已有可复核的 JVM、编译与 API 31 arm64 真实插件证据，现为 4/4；该结果只关闭自动化测试阶段，不提前关闭 R1.1 或 R1.3:

- 宿主持久语义 cache 使用 generation artifact 与带校验和的 manifest；严格执行文件与目录 fsync 及原子 manifest commit，并提供启动恢复、LRU、单项 16 MiB、总量 128 MiB、最多 32 项和损坏 generation 精确淘汰。
- cache lookup 仅在同签名 exact component 完成认证握手且最终化 semantic key 后进行，并位于输入/输出 FD claim 与 `openSession` 之前；命中仍重跑当前 `DexIndexedZipValidator`，不会继承历史验证结论。
- lookup 先打开 descriptor，再对同一 inode 复验大小及 SHA-256；成功 classloader 接管保留 cache，非中断接管失败只淘汰当次 exact generation。
- production Runtime 已在认证握手并最终化 semantic attempt key 后接入进程级 single-flight：相同 key 共享一个 producer，成功结果为每个调用方取得独立 capability。任一 waiter（包括最后一个）中断时只分离该调用方并返回取消，不触发本地编译器回退；producer 可在后台完成并填充持久 cache。最后 waiter 离开时协作取消 producer 留到 R2。
- 针对不安全 executor 拒绝或疑似 Binder 阻塞设置的熔断保持保守：一旦触发，在当前宿主进程生命周期内持续打开且不自动探测恢复；它不会被表述为已经强制终止远端或阻塞中的 Binder 工作。
- Android instrumentation 新增并逐项执行：2 个 production concurrency 方法、2 个真实插件 lifecycle 方法和 3 个真实 D8 corpus 方法。并发断言统计的是宿主越过提交点的 committed remote dispatch，而不是直接统计 provider `openSession` 调用；重型 multi-dex 语料运行时生成 7,300 个 class、合计 65,700 个方法，并作为独立长时门禁执行。

- [x] 已验证: 宿主单元测试覆盖 opt-in 默认值、provider 选择、能力不兼容、摘要不匹配、无效输出及回退；本轮 DEX 定向门禁 16 suites/149 tests，failure/error/skipped 均为 0。
- [x] 已验证: Binder 集成测试覆盖真实插件 APK、文件描述符 ownership、回调顺序、BUSY 和 Binder death；fake provider 仅作辅助测试。
- [x] 已验证: cache 测试覆盖 key、命中、并发请求合并、原子发布、损坏缓存淘汰和失败后重试。
- [x] 已验证: Java/Kotlin、single-dex/multi-dex、缺失依赖和重复加载用例最终由真实 `DexClassLoader` 执行验证。

### R1.3 真实设备矩阵

- [ ] API 24 和 25: 验证 D8 CLI fallback 与真实类加载。
- [ ] API 26: 验证 `D8Command` 分界版本。
- [ ] API 28: 验证中间版本兼容性。
- [ ] API 34 和 36: 验证现代 Android 行为与目标 SDK 边界。
- [ ] 至少覆盖一个 arm64 真机和一个 x86_64 模拟器；具体设备必须先获得用户许可。
- [ ] 每个 canonical matrix 单元记录宿主/插件版本、commit、API/ABI、输入摘要、provider identity、输出摘要和执行结果。
- [ ] 失败矩阵证据保留原样；替代设备或 smoke 通过不能覆盖原失败记录。

#### R1 退出条件

- [ ] 显式 opt-in、回退和回滚路径均可用，默认用户行为未改变。
- [ ] 真实插件设备矩阵全部通过，且未用 fake provider 冒充端到端验收。
- [ ] 用户文档提供安装、启用、诊断、禁用和回退步骤。

### R1 本轮阶段证据（2026-08-09，2026-08-10 更新）

- 状态: R1 已启动，R1.0 接入决策完成；R1.1 source wiring、R1.2 持久 cache 与 production single-flight 已落地并通过静态审阅、定向 JVM、APK assemble 与 API 31 arm64 真实插件定向门禁。R1.2 按四项精确定义为 4/4；R1.1 仍为 0/7，R1.3 全部未勾，不能把单一 API/ABI 的定向结果泛化为生产链路或设备矩阵验收。
- 默认与回滚: provider 设置默认关闭，只能显式选择同签名 exact component；启用后仅 raw `runtime.loadJar()` JAR 优先远端，失败至多回退一次内置 D8/dx，用户取消不回退，AAR 与 `defineClass()` 继续使用内置路径。
- 回退与 ownership: 宿主保留同一输入快照、输出事务、独立验证、host-only copy、原子 cache 发布与回滚 ownership；插件不能直接发布可加载产物。R1.2 源码在认证握手并最终化 semantic key 后、claim FD 与 `openSession` 前查找持久 cache，命中仍使用当前 validator 复验。
- 协商与身份: 协议版本和当次 runtime library fingerprint 在 Binder 握手后用于最终化请求，capability/ceiling 用于验证或拒绝；最小宿主构建号、固定 component/UID/signer 及同签名要求继续生效。
- R1.0 基线门禁: 从宿主 `85373a59c` 创建临时 detached worktree并运行 DEX 定向测试；10 个 suite、105 个 test，failure/error/skipped 均为 0。该结果只属于 R1.0 基线，不能替代当前 R1.1 代码与主门禁确认。
- R1.1 门禁边界: 生产接线、测试源码、文档与本地化已经落地，静态审阅未发现剩余代码阻断。当前修正版 Gradle 门禁为宿主 DEX 16 suites/149 tests，failure/error/skipped 均为 0；Android test Kotlin 编译以及 host/test APK assemble 均成功。较早门禁中的 wire 4 suites/24 tests 与 fake-provider JVM 5 suites/25 tests 也为全绿，但它们不替代真实 provider。完整 failure、FD ownership、回调顺序、回滚、身份边界和语料覆盖尚未完成，因此 R1.1 仍为 0/7。
- Cache 源码与测试: 已部署 generation manifest/checksum、严格 fsync/原子 commit、16 MiB 单项/128 MiB 总量/32 项、恢复/LRU/损坏精确淘汰及 descriptor 同 inode 复验。持久 cache 的 11 项 pure JVM、production Runtime single-flight 的 14/14 pure JVM、独立 Harness 52 项（含 6 项 cache 路径）与真实设备的同 key 合并、fresh caller capability、命中及 exact cleanup 共同覆盖 key、hit、single-flight、atomic publish、corrupt eviction 和 retry，满足 R1.2 cache 项。
- R1.2 JVM/编译门禁: 当前修正版宿主 DEX 16 suites/149 tests 全绿；Android test Kotlin 与 host/test APK assemble 成功。真实设备方法使用 host arm64 APK `181E38E8…A0A47`、严格修正版 test APK `70FAE1E8…39B0C` 与修复后插件 APK `5B6AC53B…640C4B`；三者 v2 signer certificate SHA-256 均为 `31a681fc…c213`。
- 新增 Android 方法: 2 个 production concurrency 方法覆盖相同 semantic key 的共享 producer/独立 capability，以及 follower 中断而 leader 继续发布；探针在宿主完成 committed remote dispatch 时计数，不把 provider `openSession` 的直接调用次数伪装成生产语义证据。2 个真实 lifecycle 方法覆盖阻塞 session 的 BUSY/FD/terminal，以及显式 force-stop 的 Binder death、pipe EOF 和 exact recovery。3 个真实 corpus 方法覆盖 Java/Kotlin single-dex 与重复加载、缺失依赖的 ART 解析边界，以及真实 D8 multi-dex。
- 重型 multi-dex 边界: 该 corpus 在运行时生成 7,300 个 class，每个含构造器和 8 个静态方法，共 65,700 个方法；输出解析每个真实 DEX 的 header、map 和 class_defs，并从 `classes.dex`、`classes2.dex` 各动态选择并执行一个生成类。它作为独立门禁在 21.692 s 内通过，不能泛化为其他 API/ABI。
- API 31 arm64 真实插件结果: same-key committed dispatch/fresh capabilities 1.479 s；follower interrupt/leader publish 0.583 s；BUSY/FD/callback/gate-reuse 严格修正版 2.177 s；Java+Kotlin single-dex/duplicate identity 0.555 s；missing dependency ART boundary 0.524 s；65,700-method multi-dex primary+secondary load 21.692 s；Binder-death/EOF/no-provider-terminal/rebind 严格修正版 1.355 s。各项均 PASS，测试后 workspace 为空；最终 host/test/plugin 卸载均 `Success`，fake provider 保持 absent，相关进程数为 0。
- R1.2 证据边界: 上述方法关闭的是 R1.2 四个精确定义的自动化测试项。它不覆盖 R1.1 七条生产链路的全部 failure/回退/回滚/身份门禁，也不覆盖 API 24/25/26/28/34/36 与 x86_64，因此 R1.1 保持 0/7，R1.3 全未勾。
- 并发与熔断边界: 中断任一 caller（包括最后 waiter）只 detach 并返回取消，绝不切换到本地编译器；producer 可继续在后台完成并写入 cache。last-waiter cooperative cancel 留到 R2。安全熔断一旦触发即在当前进程生命周期内保守保持打开，不声称能硬中止已阻塞工作。
- 文档门禁: 宿主 10 个 changelog JSON 与 10 locale 资源、本插件 10 个 README locale JSON 均纳入解析检查；两仓生成器连续运行两次并要求第二次无变化，最终结果见本轮交付报告。
- 证据层级: 本轮确认了定向 JVM、Android test Kotlin 编译、host/test APK assemble，以及 API 31 arm64 上真实 Binder lifecycle、production single-flight 与完整指定 corpus。它仍不能代表 R1.1 全链路或 R1.3 API/ABI 矩阵。
- 执行边界: 每个真实方法独立执行；force-stop 使用精确包同意，并在恢复后复核 workspace。`emulator-5554` API 37 与 `emulator-5556` API 25 的外部状态未被当作替代矩阵证据。
- 插件恢复边界: force-stop 暴露出旧进程留下的真实 session workspace，促成 R2 的 process-once strict canonical janitor；该恢复切片见下节，不能倒推为 R2.2 全部完成。

## R2: 诊断、取消与恢复

目标: 让失败原因可理解，让 session 在取消、超时、宿主死亡和 provider 进程死亡后具有可验证的终态。

状态: 已启动，恢复切片进行中。force-stop 真实暴露了旧 UUID workspace（0-byte `program.jar` 与空 `d8-output`）在进程死亡后残留；插件已新增 process-once strict canonical janitor，在首次 Service Binder 暴露前回收严格锚定于私有 cache 根的旧 session，拒绝越界或符号链接遍历。插件修正版门禁为 10 suites/48 tests 全通过，其中 workspace recovery 6/6；lint 0 error/27 warnings，Debug/Release assemble 均成功，Debug APK SHA-256 `5B6AC53B…640C4B`。设备更新前确认旧 UUID 仍存在；首次 bind/kill/recovery 后 workspace 只剩空 root，随后正常 D8/`DexClassLoader` 0.832 s PASS 且仍为空。该证据只完成 janitor 恢复切片；R2.2 的宿主死亡、callback 异常、全阶段取消/超时等定义仍未满足，所有 checkbox 保持未勾。

### R2.1 结构化诊断

- [ ] 接入 D8 diagnostics handler，区分 info、warning、error 和内部失败。
- [ ] 诊断保留 phase、origin/entry、位置及稳定分类；不存在可靠信息时不伪造字段。
- [ ] 保持总字节、单条文本和队列上限，明确截断标志与丢弃计数。
- [ ] 宿主展示结构化摘要，并允许用户区分输入错误、缺失依赖、desugaring、输出和 provider 故障。
- [ ] progress 只有在 `current/total` 可真实测量时才报告数值，否则只报告阶段。

### R2.2 取消、超时和终态

- [ ] 明确宿主 deadline 与 provider 清理 deadline 的 ownership，使用单调时钟。
- [ ] cancel/close/timeout/Binder death 后立即禁止发布结果并关闭不再需要的描述符。
- [ ] 明确记录 D8 CPU 工作可能无法可靠中断，不能把线程 interrupt 误报为工作已经停止。
- [ ] terminal callback 至多一次，且不会被晚到的 progress/diagnostic 越过。
- [ ] provider 进程死亡、宿主死亡和 callback 异常后 session gate 与私有临时目录最终可回收。
- [ ] 为卡住 worker 定义保守的进程级恢复策略，并验证不会发布不完整输出。

### R2.3 韧性矩阵

- [ ] 覆盖取消发生在 VALIDATING、COMPILING、PACKAGING 和 WRITING 各阶段。
- [ ] 覆盖自然超时、并发 BUSY、callback backpressure、callback 抛错和 Binder death。
- [ ] 覆盖 provider 进程被杀、宿主进程被杀、磁盘空间不足及 cache 清理失败。
- [ ] 记录 session 终态、描述符关闭、临时目录清理和新 session 可用性。

#### R2 退出条件

- [ ] 诊断预算、终态、取消和崩溃恢复都有自动化与真实设备证据。
- [ ] 文档准确区分“结果已禁止发布”和“D8 CPU 已经停止”。

## R3: 协议 V2、依赖输入与宿主缓存

目标: 支持复杂第三方库，并把 R1.2 的单 program 语义 cache 扩展到 V2 多输入，同时继续坚持 FD-only、资源有界、调用方鉴权和宿主最终验证。

### R3.0 协议设计

- [ ] V2 与 V1 可并存协商；旧宿主和旧 provider 失败方式明确且安全。
- [ ] 多 JAR/program/classpath/desugared library 只通过有界文件描述符与摘要传递，不接受任意文件路径。
- [ ] 每个输入及总输入都声明大小、SHA-256、角色、顺序和资源上限。
- [ ] runtime 与外部 classpath 指纹进入请求和 cache key，顺序语义固定。
- [ ] 定义 duplicate class、缺失依赖、冲突依赖和 unsupported bytecode 的确定失败策略。

### R3.1 职责边界

- [ ] AAR 解包、资源处理、依赖解析和规范化由宿主/构建层负责；本插件仍只消费代码输入。
- [ ] 将宿主语义 cache 扩展到 V2 多输入 key、请求合并、原子发布、淘汰和损坏恢复。
- [ ] 插件不下载 Maven/Gradle 依赖，不请求网络权限，不执行生成的 DEX。
- [ ] 自定义 desugared library 若被支持，必须有独立 capability、摘要和兼容性矩阵。

### R3.2 验收

- [ ] 覆盖多依赖、顺序变化、重复类、缺失类、不同 runtime fingerprint 和 desugared library 组合。
- [ ] 覆盖所有单项/总量上限、FD ownership、调用方取消和输出二次验证。
- [ ] V1 回归矩阵保持通过。

#### R3 退出条件

- [ ] 协议规范、实现、兼容性测试和安全审查完成。
- [ ] 复杂依赖用例在真实设备上由最终 `DexClassLoader` 执行通过。

## R4: 编译器治理与能力分离

目标: 让 D8 provider 保持单一职责，并把高风险或不同产物语义的能力放到独立、显式选择的边界中。

### R4.1 D8 升级与确定性

- [ ] 建立涵盖 Java/Kotlin 版本、desugaring、multi-dex、API 24-36 和已知失败语料的 D8 升级矩阵。
- [ ] 每次升级记录 D8 版本、输入摘要、runtime fingerprint、输出摘要和行为差异。
- [ ] 在没有重复构建证据前不声明 deterministic；若无法保证，则 cache key 必须包含 compiler identity/version。
- [ ] 为旧 D8 保留可回滚版本和兼容性说明。

### R4.2 独立 R8 provider

- [ ] `RELEASE` 继续只代表 D8 compilation mode，不静默等同于 shrinking、optimization 或 obfuscation。
- [ ] R8 使用独立 provider identity、capability、协议语义和发布历史。
- [ ] keep rules、consumer rules、mapping、seeds/usage 及 retrace 产物采用显式、有界接口。
- [ ] 反射、动态类名、JNI、序列化和 AutoJs6 脚本访问建立专门兼容性语料。
- [ ] 用户必须显式选择 R8；失败时不得悄悄退化为含不同语义的 D8 产物。

### R4.3 其他编译能力

- [ ] Java/Kotlin 源码编译保持为独立插件或构建层，先输出经过验证的 JAR，再交给 DEX provider。
- [ ] AAR 资源合并、APK 打包、签名和安装继续位于宿主构建/发布链，不进入本插件。

#### R4 退出条件

- [ ] D8 升级流程可重复且可回滚。
- [ ] R8/源码编译若落地，均拥有独立身份、安全模型、验收矩阵和发布证据。

## 阶段证据记录

完成一个阶段时，在这里追加一条简短记录；详细日志应保存在对应仓库的稳定路径中。

| 阶段 | 日期 | Commit | 结果 | 证据 |
|---|---|---|---|---|
| R0 | 2026-08-10 | 未提交 | 已完成 | 强制重跑 43 tests / 10 suites 全通过；large evidence 为 sourceBytes=66,595,045、providerLimit=67,108,864、maxHeap=62,914,560；同轮 lint 与 Debug/Release 构建均通过；仅属 JVM/本地验收 |
| R1 | 2026-08-10 | 未提交 | 进行中 | R1.0 已完成；R1.1 source wiring、R1.2 持久 cache 与 production Runtime single-flight 已落地。宿主 DEX 16 suites/149 tests 全绿，Android test Kotlin 与 host/test APK assemble 成功；API 31 arm64 上 2 concurrency、2 lifecycle、3 corpus 方法逐项通过。R1.2 为 4/4；R1.1 为 0/7，R1.3 全未勾 |
| R2 | 2026-08-10 | 未提交 | 已启动/恢复切片进行中 | process-once strict canonical workspace janitor 已通过 48/48 插件 JVM、6/6 recovery、lint 与 Debug/Release build；API 31 旧 UUID 经首次 bind/kill/recovery 后清空，正常 D8 后保持空 root；R2 checkbox 全未勾 |
| R3 | - | - | 待开始 | - |
| R4 | - | - | 待开始 | - |
