# CodeBridge 2.6.1（2026111502）误发 Compose 客户端历史记录

日期：2026-11-15（北京时间）。本次误将“在 main 开发”理解成发行 Compose 客户端；用户实际需要已开发的原生 SwiftUI 多 Agent App。以下保留真实上传和后端验证事实，不作为当前目标版本或安装推荐，也不表示该包已撤回或过期。

后续已从 `codex/swiftui-delivery` 经备份后复制整合原生成果到 main，两份原 SwiftUI 工作区保持原样。原生候选为 `1.0.0 (2611151349)`，其新构建、回归、上传与测试资格需另行取证，不能引用本记录代替。

## TestFlight

| 项目 | 已回读结果 |
|---|---|
| ASC App | `6831158430`，CodeBridge for Codex |
| Bundle / Team | `com.gejiarong.codebridge` / `7U83DS2M3Q` |
| 版本 / build | `2.6.1` / `2026111502` |
| Delivery / Build ID | `93132c7b-e896-4628-a91c-080ce965b206` |
| 处理 | `VALID`，upload `COMPLETE` |
| 内部测试 | `IN_BETA_TESTING`，已确认属于既有「内部测试」组 |
| 更新说明 | 中文说明已写入并回读一致，包含 Compose 来源、重新配对和外网前提 |
| 外部测试 | `READY_FOR_BETA_SUBMISSION`；本次未新建外部组或提交外部审核 |

归档和导出后的 IPA 均通过个人 bundle/team 与 production APNs entitlement 检查，导出 App 的严格代码签名检查通过。IPA SHA-256：

```text
2d38e9fdf7134b7171fa01cfe2450af7193a50d8beb037a6011d03bfa2f734bd
```

当时通过 `scripts/release-codebridge-ios.sh` 与 `iosApp/codebridge-compose.yml` 构建，使用现有 Distribution 证书与 profile，不复用上游身份或 Firebase 配置；生成工程沿用当时已跟踪的 SPM 版本锁。该 Compose 个人入口现已移除，发行脚本已切换到原生 `iosApp/codebridge.yml` 并校验 `CodeBridgeClient=SwiftUI`，不能用当前脚本复现本包。IPA、归档、上传回执和原始日志仅保存在忽略目录或私有缓存。

这些结果记录当时内部测试资格，不证明真实手机已经安装或完成验收，也不表示 App Store 正式上架，更不证明后续原生候选已上传或可安装。

## 云端与电脑

- 个人入口 `wss://relay.xiaowanai.cn` 当时已部署；40 个程序文件摘要与清单一致，当时 main 的 171 个构建输入逐项核对一致。备份、服务与回滚边界见[个人 relay 部署](../deploy/CODEBRIDGE-RELAY.md)。
- Mac「马可波罗」的 daemon 为 `2.6.1`，单实例、launchd 已启用且运行，8799 仅监听回环，连接个人 relay。
- 首次安装遇到该 label 的 launchd 持久 disabled 状态；恢复该服务启用后按规定安装脚本完成验证，没有另起临时 daemon。
- 隔离设备通过公网配对、E2E、真实 Codex 提示投递、PromptAck、预期回复和无错误回合；断线后重新握手并恢复同一会话历史。测试会话关闭、测试设备吊销。
- 云端已加载与个人 bundle 匹配的 APNs sender，但未向真实手机发送测试通知。

这些后端链路证据可以继续作为部署参考，但不证明原生 SwiftUI 客户端通过验收。

## 当时验证

| 检查 | 结果 |
|---|---|
| 协议 JVM | 448 项，0 失败 |
| relay | 125 项，0 失败 |
| main 新配置移动端 Desktop | 2633 项，0 失败 |
| 个人部署故障与打包测试 | 12 项，0 失败 |
| iOS | Release 归档、IPA 导出、签名与推送 entitlement 验证通过 |
| 内容 | 仓库内容、品牌兼容与商店文本检查通过 |

## 手机连接与后续验收

不要将本记录中的 Compose 版本作为当前安装推荐。原生 `1.0.0` 完成上传并获得测试资格后，需在 TestFlight 的 **Other Builds／其他构建** 中手动选择；它不会自动作为 `2.6.1` 的更新。能否列出和安装须回读 ASC 测试组并在 TestFlight 确认，详见[发行与外网连接说明](../CODEBRIDGE-RELEASE.md)。电脑需保持开机、联网和 daemon 在线；手机在外使用同一公网 relay，无须开放 Mac 的入站端口。

旧独立 CodeBridge Gateway 的协议和 Keychain 配对不能直接复用为 Pairlet 配对。相同 bundle 允许覆盖安装，不代表所有旧数据已经迁移。

仍待真实手机逐项验证：蜂窝打开与发送、审批、Wi-Fi／蜂窝切换、锁屏通知展示、点击回到原会话、后台恢复和弱网。下一阶段优先处理这份真机矩阵，再加固 launchd 安装回执、长期凭据存储与更新签名。
