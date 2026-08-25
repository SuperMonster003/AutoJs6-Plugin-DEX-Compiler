# AutoJs6 DEX 编译器

本插件让 AutoJs6 在独立进程中使用 D8 8.13.22 编译 JAR, 支持 `runtime.loadJar()` 以及 `runtime.loadJarWithClasspath()` 使用的有序编译期 classpath.

## 启用前须知

- 插件默认关闭. 仅安装 APK 不会改变 AutoJs6 的行为.
- 需要 AutoJs6 build 5270 或更高版本, 以及 Android 7.0 (API 24) 或更高版本. classpath 入口需要更新的配对宿主构建.
- AutoJs6 与插件必须具有相同签名. 签名不一致的插件无法被选中.

## 启用插件

1. 安装或升级兼容的 AutoJs6, 然后安装本插件 APK.
2. 在 AutoJs6 中打开 设置 > 关于应用与开发者, 长按应用图标进入开发者选项.
3. 打开 DEX compiler > Raw JAR compiler provider.
4. 选择本插件的服务组件并确认.

provider 摘要表示本插件已被选中; 某次加载仍可能直接命中缓存, 或使用内置回退.

## 使用与恢复

像平常一样调用 `runtime.loadJar()` 或 `runtime.loadJarWithClasspath()` 即可. 插件不会添加 JavaScript 全局对象, 也无法读取脚本的原始路径.

若插件不可用, 正忙, 超时, 编译失败或返回无效输出, AutoJs6 会用内置编译器对同一请求至多重试一次. 主动取消不会触发回退. 若要停用插件, 请在同一开发者选项页面选择 Built-in D8/dx, 然后重启 AutoJs6; 无需卸载宿主或清除宿主数据.

## 安全与限制

- 只有相同签名的 AutoJs6 宿主可以绑定编译服务.
- 编译前会检查输入大小, SHA-256, ZIP 帧结构, 条目路径, 压缩比与 class 文件; AutoJs6 会在缓存或加载前独立检查返回的 DEX ZIP.
- 输出最大为 16 MiB, 且最多包含 64 个连续的 `classes*.dex` 条目.
- 插件不请求存储或网络权限. 它只执行 D8 编译, 不执行 R8 压缩或混淆.

反馈问题时, 请附上 AutoJs6 build, 插件版本, Android API, 设备 ABI, 复现步骤与完整脚本错误. 分享日志前请移除私有路径与敏感内容.
