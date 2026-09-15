# R4 D8 upgrade gate

本目录提供纯本地的 D8 升级基线和候选比较。它只证明 JVM 中固定输入对 D8 的编译行为，不证明 APK 内运行、Binder/PFD、真实 `DexClassLoader`、设备 API/ABI 或生产兼容性。

## 固定边界

- 默认版本来自 `gradle/libs.versions.toml` 的 `r8`；生产 capability 由同一次构建生成的 `BuildConfig.D8_COMPILER_VERSION` 声明，避免依赖与协议版本漂移。
- 候选只能用显式 Gradle 属性 `d8CandidateVersion` 覆盖。撤掉该属性即回到固定版本；候选报告写入独立版本目录。
- consumer 默认只接受固定 `8.13.22`；候选必须显式传 `-CandidateEvaluation`，旧 pin `8.13.17` 的真实 catalog rollback 必须显式传 `-RollbackEvaluation`。Gate 分别记录 `evaluationKind=PINNED_DEFAULT`、`CANDIDATE_OVERRIDE` 或 `OLD_PIN_ROLLBACK`。
- `minApi` 24 至 36 是 D8 编译参数矩阵，不是 Android 24 至 36 设备矩阵。
- JVM 矩阵的 `android.jar` 来自 AGP 为当前 `compileSdk` 解析的 `sdkComponents.bootClasspath`，不拼接 SDK 平台目录名。通过声明 `@InputFile` 的 JVM 参数 provider 延迟取值，直到任务执行时才读取，避免提前创建 `Test` 任务时 AGP 尚未完成 `targetCompatibility` 配置。JVM 参数与任务输入使用同一文件。
- 成功 cell 精确编译两次并记录摘要是否相同，但所有报告和 Gate 都固定为 `determinismClaim=NOT_CLAIMED`。
- 已写出的 `FAIL` 或不可读 cell 报告不会被测试自动删除；先归档整个版本报告目录，再开始新的观察。
- 生成 cell 报告的 Gradle `Test` task 明确禁用 build cache 且永远不视为 up-to-date；Gate 输出位于 cell report 目录之外，避免输出所有权重叠。
- 每次 producer 都生成规范 UUID，并写入 v2 cell report；生产 verifier 在安全输出建立后强制校验 `-ExpectedProducerInvocationId` 为非空规范 UUID，整组报告必须来自同一次且与当前 Gradle invocation 完全一致，旧 invocation 不能混入新 Gate。参数缺失或格式错误同样会原子覆盖旧 PASS。
- Gate/比较器通过同目录临时文件原子替换输出；合法输出目标在失败或异常时也会持久化 `passed=false`，避免旧 PASS 残留。无模块依赖的启动引导先建立安全输出，因此 gate module 缺失或损坏也会覆盖旧 PASS。输出路径会逐段解析父级 symlink/junction；若与 manifest、schema、gate module、consumer 或任一输入报告别名则直接拒绝且不改输入；错误 JSON 不持久化本机绝对路径。

## 基线 Gate

```powershell
.\gradlew.bat :app:verifyR4D8UpgradeMatrix --rerun-tasks --console=plain
```

报告位于：

```text
app/build/reports/d8-upgrade-matrix/<version>/invocations/<producer-uuid>/r4D8UpgradeMatrixTest/
```

其中 60 份 cell report 记录 producer invocation UUID、compiler version、输入 SHA-256、`android.jar` runtime fingerprint、编译结果、输出摘要和连续 DEX manifest；版本目录下独立的 `gate-r4D8UpgradeMatrixTest.json` 先被写为 `passed=false`，只有本次唯一 invocation 的固定 11-case/60-cell 形状全部满足 manifest/schema/consumer 约束时才原子替换为通过。Gate 还记录 producer UUID、matrix、report schema 和路径无关 report set 的 SHA-256 绑定。

## SDK 路径与任务配置回归检查

```powershell
.\gradlew.bat --init-script scripts/r4-d8-upgrade/check-boot-classpath.init.gradle :app:testDebugUnitTest :app:verifyR4D8UpgradeMatrix --console=plain
```

该 init script 在项目配置期间提前创建 `Test` 任务，覆盖曾导致 `bootClasspath` 抛出 `targetCompatibility is not yet finalized` 的顺序；执行测试前还会确认 JVM 只收到一个 `d8.matrix.androidJar` 参数，其路径与 AGP 解析结果一致，且该文件被登记为任务输入。CI 的单元测试与构建步骤也使用此检查，SDK 目录为 `android-37.0` 等名称时无需调整脚本。

## 候选版本

PowerShell 调用 `.bat` 时使用原生参数数组，避免带点号的 `-P` 值被拆成 Gradle task：

```powershell
$gradleArgs = @(
    ':app:verifyR4D8UpgradeMatrix'
    '-Pd8CandidateVersion=8.13.23'
    '--console=plain'
)
& .\gradlew.bat $gradleArgs
```

候选不会修改 `libs.versions.toml`。若要回滚，只需撤掉 `d8CandidateVersion` 并重跑默认 Gate。

## 比较基线与候选

```powershell
$baselineProducerInvocationId = '11111111-1111-4111-8111-111111111111'
$candidateProducerInvocationId = '22222222-2222-4222-8222-222222222222'
pwsh -NoLogo -NoProfile -File .\scripts\r4-d8-upgrade\compare-r4-d8-upgrade.ps1 `
    -BaselineReportDirectory ".\app\build\reports\d8-upgrade-matrix\8.13.22\invocations\$baselineProducerInvocationId\r4D8UpgradeMatrixTest" `
    -CandidateReportDirectory ".\app\build\reports\d8-upgrade-matrix\8.13.23\invocations\$candidateProducerInvocationId\r4D8UpgradeMatrixTest" `
    -BaselineVersion 8.13.22 `
    -CandidateVersion 8.13.23 `
    -OutputPath .\app\build\reports\d8-upgrade-matrix\8.13.23\comparison-to-8.13.22.json
```

比较器先独立验证固定 `8.13.22` 基线和显式候选的两套 60-cell Gate，再要求输入摘要、runtime fingerprint、compiler outcome 和 DEX entry-name 拓扑一致；输出字节差异会被记录，但不会被当作确定性或等价性声明。这里的行为比较只到 compiler outcome/DEX 拓扑层，不声明失败诊断文本或运行时行为等价。真实默认 pin 的 promotion/rollback 由相邻 `scripts/r4-d8-promotion/` 门禁验收，不能用候选 override 代替。

## 治理逻辑自测

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\r4-d8-upgrade\test-r4-d8-upgrade.ps1
```

固定 31 项自测必须全部通过，覆盖旧 pin rollback 的显式模式与 candidate/rollback 互斥，以及缺 cell、重复 cell、版本漂移、producer invocation 混入、expected producer UUID 缺失/畸形、摘要缺失、非法确定性声明、重复次数不符、DEX manifest 乱序/缺号、同一输入集中共存的 `FAIL` 后 `PASS` 拒绝、失败结果替换旧 PASS、验证器/比较器 module 缺失或损坏时覆盖旧 PASS，以及输出路径别名不改输入。producer 使用新的 invocation 目录保存本次观测；Gate 不声称能发现已被外部删除的历史。
