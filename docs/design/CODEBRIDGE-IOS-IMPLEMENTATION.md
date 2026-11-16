# CodeBridge iOS 原生实现

目标：以已确认的 iOS 原型实现 CodeBridge，复用 Pairlet 通用能力，沿用旧 CodeBridge 安装身份，验证后上传 TestFlight。

2026-11-15 已将 `codex/swiftui-delivery` 的完整 SwiftUI 多 Agent 客户端经备份后复制整合到 `main`，两个原工作区保持原样，并交付原生 `1.0.0 (2611151349)` 内测。营销版本固定 `1.0.0`，build 按北京时间 `YYMMDDHHmm` 生成；2026-11-16 修复观察模式与状态更新，当前验证和分发状态见[发行说明](../CODEBRIDGE-RELEASE.md)。

2026-11-07 的自有 relay 部署、实网配对、真实 Codex 回合、真机 APNs production 发送及 `2.0 (2026110703)` 内部 TestFlight 上传属于下文历史证据。真机锁屏通知交互、持续回归和与 Codex 官方 Mac App 共用同一运行端的兼容性仍需继续验证。

## 工程入口与身份

- 原生工程定义：`iosApp/codebridge.yml`，从仓库根运行 `xcodegen generate --spec iosApp/codebridge.yml` 生成 `iosApp/CodeBridge.xcodeproj`；个人发行入口为 `scripts/release-codebridge-ios.sh`，归档必须含 `CodeBridgeClient=SwiftUI`。
- Bundle ID：`com.gejiarong.codebridge`；Team：`7U83DS2M3Q`；App Store Connect App ID：`6831158430`。
- UI 源码：`iosApp/CodeBridge/`。SwiftUI 提供导航、工作区列表、设备/Agent 管理、通知、用量和额度；iOS 26 使用系统 Liquid Glass，旧系统回退为 Material。
- 数据适配：`CodeBridgeRuntime.kt`，由同一个 `PocketRepository` 与 `FleetCoordinator` 管理连接和状态，避免再建一套配对、审批或 Agent 执行逻辑。
- SwiftUI 已实现原生对话、流式消息、历史分页、停止/发送、模型、思考深度、权限模式、Agent/设备切换、工作区会话、语音、照片/文件附件、审批、Diff、文件、通知、Token 用量和套餐额度；复杂数据仍由 Kotlin/Native 公共层投影，界面不直接调用后端 Agent CLI。

## 功能与数据边界

- 外部客户端持有的会话展示“观察模式 · 仅查看”，隐藏不可用的输入框；允许接管时显示手动入口。Codex Desktop 持有线程时，接管通过 `~/.codex/ipc/ipc.sock` 的 follower 请求进入原 thread，不启动第二个 app-server、不改 thread ID、不创建分支；Desktop 不接受 app input 时明确拒绝，原会话保持不变。只读策略仍然禁止接管。
- 原生列表使用 `NativeSessionActivity` 的最新执行状态覆盖加载时的 `SessionSummary.live`。当前可控会话跟随流式回合状态，后台任务仍保留运行标记；观察会话优先使用原生生命周期事件，转录活跃时间不能冒充任务执行证据。首次列表尚未返回或旧 daemon 不提供逐会话状态时保留未知语义。
- 当前回合结束时触发一次目录刷新；前台保留约 12 秒的跨会话校准，观察模式也参与校准。下拉刷新同时重读已加载工作区。当前观察会话的原生结束事件可先于下一次目录轮询生效；未打开的外部会话受轮询与网络延迟影响，不承诺全部状态毫秒同步。

- 首页工作区默认展开会话，前 3 条预览，可展开更多；工作区内直接创建任务。后台列表读取不得写入浏览路由或切换聊天。
- Agent 管理支持逐项启用/关闭、拖拽排序和按电脑持久化；默认 Agent 可在管理页或首页图标长按菜单设置。首页设备和 Agent 共用顶部栏，只展示已启用项；会话行将 Agent 图标放在开头，把运行中、完成、出错、待确认和空闲状态固定在最右侧。
- 切设备时清除工作区缓存；Agent 筛选不隐式修改默认 Agent。
- 原生对话支持流式消息；普通工具步骤折叠为一条活动摘要，点击后才展开，失败数量与运行状态仍保留在摘要中。
- Token 统计读取 daemon 汇总结果，按回复所覆盖的 Agent 和时间范围标注；套餐额度来自账号窗口，二者分开展示。
- 缓存命中遵循 `cacheRead / (input + cacheRead)`，没有数据时显示暂无数据，不用 0 代替未知。
- 通知设置读取系统权限与 relay 注册状态；本地通知列表保留系统已送达的摘要与会话路由，最多 200 条。
- 隐私同意之前不连接、配对、处理深链或推送路由；Demo 在同意后仍保持完全离线。

## 升级与服务

沿用安装身份可覆盖旧版 App，但旧 `bridge/v1` 与 Pairlet `pocket/*` 协议不同，旧凭据不能直接迁移；保留旧资料，并在首启解释重新配对。

本 Fork 的正式 relay 已部署在 `wss://relay.xiaowanai.cn`，使用独立 Nginx TLS、systemd 服务与 SQLite 存储。2026-11-07 已将旧 `codebridge-relay` 容器停止并保留回滚数据，保留 `frps` 等其他服务；本机 Pairlet daemon 已切换并只保留一个实例。APNs production Key 已配置，relay 启动日志确认 push sender 就绪。

## 当前整合范围（2026-11-15）

整合原生 UI、`CodeBridgeRuntime`、`NativeChatProjection`、工作区会话缓存与模型参数，以及相关 Demo 数据和测试。保留 main 的共享 Compose 界面实现，不导入原工作区中与原生编译无关的 Compose 改造。原工作区的 daemon 本地控制请求 35 秒超时修复属于独立改动，本次未带入 main。

## 历史交付验收（2026-11-07）

以下为当时工作区的证据与剩余验收，不代表 2026-11-15 整合后的候选已经通过：

1. **已取得**：SwiftUI Debug/Release Framework、模拟器构建与安装；首页/工作区、新建任务、模型/思考、分类、通知与统计交互有 UI 测试和实网截图。
2. **已取得**：模拟器经 `wss://relay.xiaowanai.cn` 完成真实六位码配对、加密握手、会议打开、真实 Codex 提示与回复；真机随后完成配对、会话打开、历史恢复、模型/额度/用量读取、设置变更和真实对话。附件、Diff、审批的专项持续回归仍需在对应测试与真机交互中逐项记录。
3. **已取得**：`aps-environment=production`、relay token 注册入库、真机 production APNs 发送成功日志。锁屏展示、点击通知进入正确会话及后台弱网恢复仍需真机确认。
4. **当时回归通过**：`check-all.sh` 的 44 个任务通过，内容检查、App Store 元数据检查和 `git diff --check` 通过；SwiftUI 深色模式 UI 套件 3 项通过、1 项实网用例按设计 skip、0 失败，独立实网用例 1 项通过。
5. **当时内部交付完成**：`2.0 (2026110703)` 已归档、签名、验证并上传；ASC 回读 `processingState=VALID`、`internalBuildState=IN_BETA_TESTING`，内部组“内部测试”设置为 `hasAccessToAllBuilds=true`。外部组当时为 `READY_FOR_BETA_SUBMISSION`，未提交外部 Beta 审核。

本地构建日志、模拟器截图和 TestFlight 产物放已忽略的 `_local/`、`dist/`，不得将构建或 Demo 测试结果写成真实设备验收。

## 官方 Codex Mac App 与手机共用会话

用户于 2026-11-07 明确电脑端为 Codex 官方 Mac App；目标为共同操作同一会话，不以只读观察、共享历史或分叉接管替代。

当前 Pairlet 的 `Conversation` 可以向多个设备分发消息，`SessionRegistry` 对同一 daemon 已运行的会话执行 reattach。CodexBackend 默认启动每个会话自己的 `codex app-server`；官方 App 仍保持自己的 writer。外部仍活跃的 Codex 会话默认只读观察；用户确认接管后，daemon 通过官方 App 的本机 IPC follower 把消息、纠偏和停止发送给原 owner，并继续 tail 同一 rollout。这条路径不会 fork，也不要求两个 app-server 同时持有 writer。

2026-11-07 检查的本机官方 App 随附版本为 `0.167.0-alpha.3.2`。当时只读检查其启动实现发现 `CODEX_APP_SERVER_USE_LOCAL_DAEMON` 与 `CODEX_APP_SERVER_WS_URL` 两个连接入口；它们是该版本安装包的实现证据，不视为稳定公开配置承诺，也不证明当前私有会话可以直接附加。官方 [app-server 文档](https://learn.chatgpt.com/docs/app-server)描述了 stdio、WebSocket、Unix socket 的连接方式，以及按 thread id 恢复与订阅会话。

桌面同 thread follower 依赖官方 App 的非公开 IPC，升级官方 App 后必须重新验证。验收项仍是：

- Mac 与手机看到相同 thread id，恢复和重连不产生隐式 fork。
- 两端分别发消息，另一端显示用户消息、流式回复与最终状态。
- 审批只完成一次，两端及时反映结果。
- 手机断线或退出不终止官方 App 上的任务；官方端离开页面不抢走手机连接。

自动化路径已覆盖 owner discovery、follower 请求与“不创建 daemon writer”的路由；真实官方 App 与物理 iPhone 的双端发送、流式消息回传、停止和 App 升级兼容仍需专项验收。模拟器或 fixture 结果不能替代物理真机证据。

原工作区的只读探针 `scripts/probe-codex-shared-runtime.py`（需要 Python `websockets` 包）通过已存在的 Unix WebSocket 完成 initialize 与 thread/loaded/list，不启动 daemon、不创建/恢复会话、不发送消息；该脚本本次未带入 main，不能作为当前可运行入口。2026-11-07 实际返回 initialized=true、loadedThreadCount=0，证明当时共享 socket 可连接，不证明官方 App 当前会话已经使用它。`codex app-server proxy` 透传的是 socket 字节，不能直接用 JSONL 代替 WebSocket 握手。

## 历史验证记录（2026-11-07）

- Kotlin/Native `linkDebugFrameworkIosSimulatorArm64` 首次构建通过。
- `CodeBridge` SwiftUI 工程模拟器构建、安装与启动通过，使用独立的 iPhone 17 / iOS 27.0 模拟器。
- `CodeBridgeUITests.testFirstRunDemoNavigation`：1 项通过、0 失败，覆盖同意披露、进入离线 Demo、首页 Tab 和 Token 用量路由。
- 工作区后台加载测试和既有返回导航测试通过。测试先复现后台会话列表错误接管页面，再在回复入口区分后台预览与用户浏览，验证多个工作区缓存和断开后的隔离。
- `SwiftUI-LivePairing-v5.xcresult`：1 项实网测试通过、0 skip；覆盖新 relay 配对、新建 Codex 会话、真实提示 `PAIRLET_SWIFTUI_SMOKE_OK`、会话恢复与截图。
- 普通 SwiftUI 深色模式回归 `ui-suite-r4-dark.xcresult`：3 项通过、1 项 skip、0 失败；覆盖 Agent 开关、排序入口、收藏星移除、会话状态、新建会话、流式对话、活动折叠、模型/思考/权限和 Token 用量。独立实网 `CodeBridgeLive-r3-174722.xcresult`：1 项通过、0 skip。
- 通知与统计专项 `ui-notifications-statistics-current.xcresult`：1 项通过、0 失败；覆盖通知首页与权限设置、Codex 套餐额度和 Token 用量统计周期。前述深色模式回归包同时覆盖本轮完整 App 交互；新增实网用例按设计跳过，避免普通 UI 回归依赖固定设备在线。
- 当时 `pairlet pair` 的 25 秒设备等待长轮询会被本地控制 HTTP 客户端的较短超时误报为 `daemon_unreachable`。原 `swiftui-delivery` 工作区曾将请求超时设为 35 秒并补充回归断言，聚焦测试、44 个检查任务及内容检查通过；该独立修复未整合到当前 main，不能将此历史结果用于描述当前 daemon。
- 真机 `XcBNtptH…` 已通过 relay 配对并持续握手；daemon 日志记录真实 `SendPrompt`、`OpenSession`、`FetchModels`、`FetchUsage`、quota 与 `SetApprovalPrefs`。relay 在 16:46:58 向该真机发送 `platform=apns`，调用的是 production 路径。
- 发行：`CodeBridge-2.0.2026110703.ipa`，SHA-256 `6ef96bc60267d4ec675bc0e6b3b622717f65600a5d987d108e2d8dd5a6143222`；Bundle ID `com.gejiarong.codebridge`，Delivery UUID `b682f872-a7ee-4fa8-bed2-7403a0c0c081`；`altool --validate-app` 与 `--upload-app` 均成功。ASC 回读 `processingState=VALID`、`internalBuildState=IN_BETA_TESTING`。
- 构建产物与 `xcresult` 保存在已忽略的 `dist/`；模拟器推送和内部 TestFlight 可安装状态不代替真机锁屏送达、点击路由或语音等人工验收。
