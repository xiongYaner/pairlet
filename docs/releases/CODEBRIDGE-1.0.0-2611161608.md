# CodeBridge 1.0.0（2611161608）原 thread 接管与实时状态

日期：2026-11-16（北京时间）。客户端为 `iosApp/codebridge.yml` 构建的原生 SwiftUI 多 Agent App；Bundle ID `com.gejiarong.codebridge`，Team `7U83DS2M3Q`，`CodeBridgeClient=SwiftUI`。营销版本保持 `1.0.0`。

## 修复内容

- 对官方 Codex Mac App 正在持有的会话执行“接管”时，daemon 通过本机 `~/.codex/ipc/ipc.sock` 的 `thread-follower-*` 请求把提示、纠偏和停止操作交给原 owner；thread ID 保持不变，不创建分支，也不启动第二个 writer。
- Desktop owner 不接受 App 输入或 IPC 不可用时返回 `desktop_control_unavailable`，原会话保持不变；不再静默回退到 `thread/fork`。
- 观察会话的提示、纠偏和中断继续转发到原 owner；同一 rollout 的逐会话执行状态持续更新，避免任务已结束仍显示“运行中”。
- 原生界面明确说明“同一个会话、thread ID 不变、不会创建分支”，并提供手动接管入口。观察流中的 `idle` 不再被误记成“完成”，历史旧完成消息也不再被误记为未读。

## 验证

- Daemon 定向测试通过：`SessionRegistryDesktopControlTest`、`SessionRegistryReadOnlyObserveTest`、`CodexDesktopIpcTest`。
- 移动端共享层定向测试通过：`NativeSessionActivityTest`、`NativeObservationTakeoverTest`、`NativeChatProjectionTest`。
- SwiftUI 状态单测 `5/5` 通过。清空模拟器 App 容器后，4 个常规 UI 流程通过、0 失败；首次失败由旧配对状态污染导致。
- `git diff --check` 通过。Release archive/export、`CodeBridgeClient=SwiftUI`、`1.0.0 (2611161608)`、Distribution 签名与 production APNs entitlement 均通过。
- IPA SHA-256：`2f38fc71d23974fb39dd2dd28e3e57e020e09b530b7febdca6e966be96fe2174`。

完整 daemon 全量测试此前曾因无关用例中断，未作为本次通过证据。尚未在真实 iPhone 与官方 Codex Mac App 之间完成同 thread 双端并发验收；fixture 和模拟器不能替代该项。

## 分发与运行状态

已上传 App Store Connect 并回读：

| 项目 | 结果 |
|---|---|
| ASC App | `6831158430` |
| 营销版本 / build | `1.0.0 (2611161608)` |
| Delivery / Build ID | `986d334c-c102-433f-9778-3d33eec1e710` |
| 处理状态 | `VALID` |
| 内部构建状态 | `IN_BETA_TESTING` |
| 内部测试组 | `805eaeda-c32c-4eb9-800e-16b9040ff84d`，已包含本 build |
| 中文测试说明 | 已写入并回读一致 |
| 外测状态 | `READY_FOR_BETA_SUBMISSION`，未创建外测审核 |

本机 daemon 已更新并完成单实例校验：daemon 进程数 `1`、relay socket 数 `1`。手机安装本 build 后保留现有 App 数据和配对；如当前安装的是 `2.6.1`，在 TestFlight 的“其他构建”中选择 `1.0.0 (2611161608)`。TestFlight 内测资格不等于 App Store 正式上架。
