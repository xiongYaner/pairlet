# main 的 CodeBridge 发行与外网连接

本 Fork 在 `main` 维护 Compose 客户端，使用个人 CodeBridge 应用身份：`com.gejiarong.codebridge`、Team `7U83DS2M3Q`、ASC App `6831158430`。两份未提交的 SwiftUI 工作区不参与此发行入口。

## iOS 构建

- 工程源：`iosApp/codebridge-compose.yml`，生成的 `CodeBridgeCompose.xcodeproj` 不进入 Git。
- 共享界面和运行时来自 `main`；上游 `iosApp/project.yml` 继续保留，不能误用它发布到个人 App。
- 个人 target 不包含上游 Firebase 配置；没有配置时现有代码关闭遥测。不得为了通过构建复制其他账号的分析配置。
- 使用本机已安装的 CodeBridge App Store profile 与对应 Distribution 证书。私钥、profile 和 ASC API key 留在本机。

先回读 ASC 的最高版本和 build，再执行：

```bash
VERSION=2.6.1 BUILD_NUMBER=<未使用的构建号> bash scripts/release-codebridge-ios.sh
```

脚本只归档、导出和验证签名/APNs entitlement，不上传。上传后应分别确认处理为 `VALID`、加入自己的内部测试组、测试组关联和内部测试可用状态。TestFlight 不等于 App Store 正式上架。

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

相同 bundle ID 允许覆盖安装，但旧独立 `codex-bridge` 客户端的 `bridge/v1` 与当前 `pocket/*` 协议不同，旧 Keychain 配对不能直接复用；首次使用此 Compose 发行版应配对到对应电脑。旧 Pairlet SwiftUI 试做版使用同一套 NSUserDefaults 运行时存储，但是否能恢复原电脑仍取决于该电脑原身份是否保留。

`RelayEndpoint.DEFAULT` 使用个人 relay；已保存的官方 Pairlet 端点仍映射到上游 operator，自托管地址保持原样，避免将已有凭据静默发给另一运营方。

外网验收应分别记录蜂窝打开会话、真实发送、审批、断线恢复、后台与 APNs。服务器健康和构建可安装不能替代真实手机验收。
