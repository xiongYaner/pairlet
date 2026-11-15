# CodeBridge 个人 relay 部署

本 Fork 使用 `wss://relay.xiaowanai.cn`，Nginx 终止 TLS，再转发到 `127.0.0.1:9000`。它与上游 `relay.pairlet.cn` 属于不同运营者，不共享配对数据库或凭据。

## 现有服务与数据

| 项目 | 路径或值 |
|---|---|
| systemd 服务 | `cc-pocket-relay`，运行用户 `ccpocket` |
| 程序 | `/opt/cc-pocket-relay/bin`、`/opt/cc-pocket-relay/lib` |
| SQLite | `/var/lib/cc-pocket-relay/relay.db` |
| 推送与分析配置 | `/etc/cc-pocket-relay/` |
| Nginx 配置 | `/etc/nginx/conf.d/relay.xiaowanai.cn.conf` |
| 公网健康检查 | `GET https://relay.xiaowanai.cn/healthz` |

上游 `scripts/redeploy-relay.sh` 使用 Caddy 并固定上游域名，不能拿它部署个人 Nginx 服务器。个人部署不改 Nginx、systemd 单元、推送凭据或其他业务服务。

## 构建与部署

```bash
JAVA_HOME=/path/to/jdk17 ./gradlew :protocol:jvmTest :relay:test :relay:installDist
bash scripts/deploy-codebridge-relay.sh --host <已验证的个人服务器SSH目标>
```

该入口需要已有的 SSH 密钥或 SSH 配置，不读取、保存或打印密码。只有小涂密码凭据时，可先生成可校验的包，再通过小涂已固定主机指纹的传输通道上传；不要把秘密填进命令行。

```bash
bash scripts/deploy-codebridge-relay.sh --prepare-only --output /tmp/codebridge-relay-release
```

生成的 `dist.tgz` 包含 bin/lib、服务端切换脚本、`release.json` 和 `dist.sha256`。清单记录来源提交、构建输入的 SHA-256 指纹以及产物逐文件摘要；工作树有尚未提交的发布配置时，不能只用 HEAD 代替产物来源。

每次使用新的输出目录。已有 `payload` 会被拒绝，避免新产物混入旧 jar；已写入部署 `result` 的 staging 也不能再次执行，避免重复停服或覆盖原回执。

## 切换与回滚边界

1. 在现有服务运行时上传 staging，核对 archive 与逐文件 SHA-256。
2. 以 transient systemd unit 运行 `deploy/codebridge/apply-relay.sh`；SSH 断开后服务器继续负责恢复。
3. 获取部署锁，在 `/opt/cc-pocket-relay/.deploy-backups/` 保存旧程序、unit 快照和一致的 SQLite 在线备份。
4. 完成全部准备后短暂停止 relay，用同文件系统的 rename 替换 bin/lib，再启动并验证回环健康。已有 WebSocket 会短暂断开并重连。
5. 服务启动或健康失败时只恢复旧程序，继续使用当前数据库。不要用旧数据库备份覆盖上线后的新配对和其他写入。

结果写入 staging 的 `result`：`ok`、`failed`、`rolled_back` 或 `rollback_failed`。结果未知时，先读取 `result`、`job.log`、`backup-path` 和该 transient unit 状态，不能盲目重复切换。

成功后还要验证公网 GET 健康、TLS，以及隔离身份的配对／鉴权／双向密文转发。不要运行会另起本机 daemon 的旧 smoke 脚本，也不要向真实设备发送测试推送。公网健康不等于 iOS 后台、蜂窝或 APNs 已验收。

本地故障注入测试使用临时目录和假的 systemctl/curl；不会启动或重启真实服务：

```bash
python3 -m unittest scripts.tests.test_codebridge_relay_deploy -v
```

## 2026-11-15 部署验证

个人 relay 已完成程序更新，原有 nginx、推送/分析配置与数据库保持原位。远端 40 个程序文件与发行清单逐项 SHA-256 一致；在线数据库备份完整性检查为 `ok`，回环与公网健康均通过。

发行清单记录准备时的 HEAD `36d32b88`，同时记录精确构建输入指纹 `1ecc47d75cd635240c92e6bdc3790d5eb3d813d40d6394a7170ec2be6e6536a5`；这些输入已与后续 `main` 的个人 relay 配置提交逐项比对一致。协议 448 项和 relay 125 项测试通过。

独立测试身份完成公网签名鉴权、六位码兑换、设备认证、P-256 握手帧和双向 AES-GCM 密文转发，测试设备随后吊销。测试没有启动第二个产品 daemon，也没有向真实手机发送推送；不能据此声称真机蜂窝、后台或 APNs 已验收。原始回执保存在仓库外。
