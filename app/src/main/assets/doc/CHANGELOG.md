******

### 版本历史

******

# v1.1.0

###### 2026/08/27

* `提示` `runtime.loadJarWithClasspath()` 需要配对的 AutoJs6 build 5274 或更高版本; 普通 `runtime.loadJar()` 继续兼容 build 5270 或更高版本
* `新增` 支持 V1.1 有序编译期 classpath: program JAR 可引用外部 API JAR, classpath 只参与编译, 不会打包进 DEX 或自动加载
* `修复` 兼容长度声明一致且在文件边界精确结束的标准 ZIP/JAR archive comment, 同时继续拒绝歧义 EOCD, 长度不一致和尾随数据
* `修复` 在 Release 压缩构建中完整保留嵌入式 D8 引擎及其服务提供者, 使生产 APK 可以正常编译 JAR
* `优化` 提供有界且脱敏的 D8 info/warning/error 诊断, 包含可用的来源, archive entry 与位置元数据, 便于定位插件编译失败
* `优化` 将 D8 内部并行编译限制为两个工作线程, 降低大型 JAR 冷编译的峰值内存, 不改变输出与缓存语义
* `依赖` 升级 Google R8 库至 8.13.22 (提供 D8 编译器)

# v1.0.0

###### 2026/08/08

* `提示` 首个正式版本. 安装后默认不生效, 需在 AutoJs6 开发者选项中手动启用; 详细步骤见 README 的 "安装与使用" 章节
* `新增` 作为 AutoJs6 的外部 DEX 编译插件: 脚本调用 `runtime.loadJar()` 加载 JAR 时, 可由本插件代替内置编译器完成 JAR 到 DEX 的编译
* `新增` 编译在插件独立进程的私有沙箱中进行, 与 AutoJs6 相互隔离; 插件失败或不可用时, AutoJs6 至多自动回退一次到内置编译器
* `新增` 编译前严格校验输入 JAR 的大小, SHA-256, ZIP 结构, entry 名称与 class 内容, 拒绝畸形, 超限或被篡改的输入
* `新增` 支持 DEBUG 与 RELEASE 编译模式, multi-dex 输出与 minApi 24 至 36; 输出为连续编号的 `classes*.dex` ZIP 并回报实际大小与 SHA-256
* `新增` 兼容 Android 7.0 (API 24) 及以上设备; API 26+ 使用 D8Command, API 24/25 自动使用 D8 CLI 兼容路径
* `新增` 仅与同签名的 AutoJs6 通信 (受 `org.autojs.permission.PLUGIN` 权限保护), 不申请网络与存储权限
* `新增` 纯 JVM 实现, 单个 universal APK 覆盖所有设备架构; 附带 10 种语言的界面, README 与应用内说明
* `依赖` 附带 Google R8 库 8.13.17 (提供 D8 编译器)
