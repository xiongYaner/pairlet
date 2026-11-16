# main 的 CodeBridge 发行与外网连接

本 Fork 在 `main` 维护原生 SwiftUI 多 Agent 客户端，使用个人 CodeBridge 应用身份：`com.gejiarong.codebridge`、Team `7U83DS2M3Q`、ASC App `6831158430`。完整成果已从 `codex/swiftui-delivery` 经备份后复制整合；该工作区与 `codex/app-foundation` 原件保持原样。

2026-11-15 的 `2.6.1 (2026111502)` 是误发的 Compose 客户端，见[历史记录](releases/CODEBRIDGE-2.6.1-2026111502.md)。原生 `1.0.0 (2611151349)` 已完成内部 TestFlight 交付；2026-11-16 的原 thread 接管、手动接管入口与实时状态修复已交付为 `1.0.0 (2611161647)`，包含真机发现的会话列表刷新补充，验证和实际分发状态见[本次发行记录](releases/CODEBRIDGE-1.0.0-2611161647.md)。

## iOS 构建

- 工程源：`iosApp/codebridge.yml`，UI 源码：`iosApp/CodeBridge/`；生成的 `iosApp/CodeBridge.xcodeproj` 不进入 Git。
- SwiftUI 界面通过 Kotlin/Native `CodeBridgeRuntime` 复用共享数据、配对和连接层；上游 `iosApp/project.yml` 不能用于个人发行。
- 个人原生工程不引入 Firebase 或 Sentry Swift 包。不得复制其他账号的分析配置。
- 版本固定为 `1.0.0`；build 使用北京时间 `YYMMDDHHmm`，例如 `2611151349`。不得为了高于历史包而自行修改营销版本。
- 使用本机已安装的 CodeBridge App Store profile 与对应 Distribution 证书。私钥、profile 和 ASC API key 留在本机。

先回读 ASC 的最高版本和 build，再执行：

```bash
VERSION=1.0.0 bash scripts/release-codebridge-ios.sh
```

脚本按北京时间生成 build；需要指定时传入 `BUILD_NUMBER=YYMMDDHHmm`，重试上传前必须确认该 build 是否已占用。

脚本只归档、导出和验证签名、production APNs entitlement 与 `CodeBridgeClient=SwiftUI`，不上传。上传后应回读 ASC，分别确认版本/build、处理为 `VALID`、测试组关联和内部测试可用状态。TestFlight 不等于 App Store 正式上架。

### 已有更高营销版本时如何安装

历史上同一 App 曾有 `2.6.1`，其后营销版本固定为 `1.0.0`；更大的 build 号不能覆盖营销版本的顺序。其他营销版本和早期构建已按用户要求设为过期，后台仍保留历史。如手机仍安装较高营销版本，在 TestFlight 的 **Other Builds／其他构建** 中选择当前有效的 `1.0.0` build。已有 `1.0.0` 的手机直接更新；可安装资格仍须回读正确测试组，不能只凭 `VALID` 承诺。

## 手机在外连接

1. 电脑安装并运行唯一的 daemon，连接 `wss://relay.xiaowanai.cn`。
2. 电脑运行已安装路径下的 `pairlet pair`，在 App 扫码或输入仍有效的六位码。
3. 配对完成后，手机与电脑分别主动连接同一个公网 relay，内容经过端到端加密。

电脑需要保持开机、联网，daemon 需要持续运行；无须开放电脑的 8799 入站端口。锁屏、休眠和合盖导致电脑离线时，云端中继不能代替电脑执行任务。

当前 Mac 的安装命令：

```bash
JAVA_HOME="$(/usr/libexec/java_home -v 17)" RELAY=wss://relay.xiaowanai.cn \
  bash scripts/update-local-daemon-detached.sh
"$HOME/Library/Application Support/cc-pocket/cc-pocket-daemon/bin/pairlet" pair
```

安装脚本保留活会话确认门，检测到其他会话时不能自行 `FORCE=1`。六位码和配对链接是短期凭据，不写入提交、发布说明或公开日志。

## 升级边界

相同 bundle ID 保持应用身份，但安装资格仍受上面的版本与 TestFlight 条件限制。旧独立 `codex-bridge` 客户端的 `bridge/v1` 与当前 `pocket/*` 协议不同，旧 Keychain 配对不能直接复用。原 Pairlet SwiftUI 版与误发 Compose 版使用同一套 NSUserDefaults 运行时存储，但是否能恢复原电脑仍取决于该电脑原身份是否保留；没有有效配对时重新配对到对应电脑。

`RelayEndpoint.DEFAULT` 使用个人 relay；已保存的官方 Pairlet 端点仍映射到上游 operator，自托管地址保持原样，避免将已有凭据静默发给另一运营方。

外网验收应分别记录蜂窝打开会话、真实发送、审批、断线恢复、后台与 APNs。服务器健康和构建可安装不能替代真实手机验收。
