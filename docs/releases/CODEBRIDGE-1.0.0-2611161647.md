# CodeBridge 1.0.0（2611161647）真机会话列表刷新

日期：2026-11-16（北京时间）。原生 SwiftUI 多 Agent 客户端，工程入口 `iosApp/codebridge.yml`，Bundle ID `com.gejiarong.codebridge`。版本固定 `1.0.0`。

## 真机发现与修复

通过 iPhone 14 Pro Max 镜像操作真实配对，独立测试任务只回复文字、执行 `sleep`，不修改工作区文件。

- 新建任务、消息送达、流式回复、工具执行、聊天页运行与结束状态、停止任务已实际走通；全程未因状态更新而重启 App。
- 从手机接管当前官方 Codex Mac App 会话后发送 `QA-PHONE-OK`，当前桌面会话实际收到该消息。daemon 日志记录 `SAME-THREAD CONTROL`，原 thread ID 保持不变。
- 发现新建会话完成后，返回列表没有出现、搜索也找不到。原因是原生定时校准只请求 `ListDirectories`，已加载工作区的会话行缓存没有重新读取；重新挂载工作区卡片后才会请求 `ListSessions`。
- 本次增加已加载工作区的会话列表刷新，在前台校准、任务完成及退出聊天时调用，并覆盖新建聊天所在工作区。保留既有请求去重与响应路由，避免重复请求或改变浏览位置。

## 本地验证

- `WorkspaceSessionsTest`：3 项通过，其中新增用例覆盖工作区卡片不重新挂载时刷新新会话、请求去重、缓存替换和浏览位置不变。
- `NativeSessionActivityTest`：9 项通过。
- `NativeObservationTakeoverTest`：1 项通过。
- 共 13 项，0 失败、0 错误、0 跳过。
- 仓库内容检查通过；Release archive/export、Distribution 签名、production APNs entitlement、`CodeBridgeClient=SwiftUI`、版本/build 校验通过。

首次真机功能验证时安装来源与 TestFlight 详情存在版本显示差异，不能将这组结果直接等同于最终发行包验收。随后在 TestFlight“以前的 Build”中明确安装 `2611161647`，首启测试说明核对版本/build；现有配对与历史保留。最终包中新建 `QA1647: Reply OK. Do not use tools.`，收到 `OK` 后直接返回列表，新会话出现并显示“完成”，无需手动刷新或重启。镜像短暂暂停后已恢复；恢复后需要重新手动接管。

## 尚未通过的验收

同一工作区存在多个外部 Codex 会话时，仍在运行的旧会话可能显示“完成”。本次当前桌面会话只有 `task_started`、没有后续 `task_complete`，但在独立测试任务完成后出现该错误标记。`CodexTranscriptScanner.activeSummaries` 按工作区只返回最新一条顶层 rollout，`DirectoryService` 因而缺少较旧但仍活跃的 thread；原生列表把缺失活动记录当作不运行，触发完成标记。另有基于 mtime 的 `live` 启发式，应在后续修复中一起替换为逐 thread 生命周期和实际 owner 证据。

该问题尚未修复，不能将本轮记录表述为“所有功能无异常”或“多外部会话实时状态验收通过”。审批、附件、语音及所有 Agent 的完整矩阵也未在本次真机测试中逐项覆盖。

## 分发状态

`1.0.0 (2611161647)` 已上传并回读 `VALID / IN_BETA_TESTING`，已有内部测试组包含该构建，中文测试说明回读一致。Delivery / Build ID：`106b381d-c5ba-40b9-a627-4e4afad0aed4`。仅内部测试，不提交正式商店审核。

原始日志与截图保存在已忽略的 `_local/phone-qa-20261116/`，安装包在 `_local/releases/codebridge-native-1.0.0-2611161647/`。

## 2026-11-16 暂停交接

用户要求本阶段告一段落，提交并推送 main，清理本轮本地测试程序；不继续开发或发版。两个原 SwiftUI 开发工作区保持原样，手机配对与单实例 daemon 保留。

提交前重新运行的定向检查：daemon 24 项、共享移动层 49 项，均为 0 失败、0 错误、0 跳过；仓库内容检查与 diff 格式检查通过。SwiftUI、签名和发行包验证沿用上述已完成的本轮证据，未重跑全量 daemon 测试。后续首先修复“同工作区多个外部 Codex 会话的状态误判”，再做长任务、并行任务、审批及断线恢复的真机矩阵。
