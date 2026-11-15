# 2026 年 9 月外部分发候选

这是未发布草稿的历史索引，不是当前安装或发布入口。正式配置使用 `packaging/homebrew/`、`packaging/scoop/` 和[发布手册](../RELEASE.md)。

2026-11-15 整理时移除了 `packaging/pairlet-candidates/`：这些候选仍固定在 1.9.7／1.9.8，不被构建、安装脚本或 CI 读取。当前发布基线为 2.6.1，不能把旧版本、哈希和 Gradle 8 配方当作新版本的分发输入。

## 原始材料与恢复

最后保留这些文件的完整来源提交是 `40de8b56ab8944bdcf114e772898433b5fa16721`。

| 原路径（相对 `packaging/pairlet-candidates/`） | 当时用途 |
|---|---|
| `README.md` | 汇总外部分发候选及其验证边界 |
| `homebrew/Casks/pairlet.rb` | 探索旧 Cask 更名，基于 1.9.7 |
| `homebrew/cask_renames.json` | 旧 Cask 名到新名的映射候选 |
| `homebrew/Formula/pairlet.rb` | 基于 1.9.8、Gradle 8 的源码 Formula 草稿 |
| `homebrew/FORMULA-STATUS.md` | 当时的构建结果、阻碍和送审前提 |
| `scoop/bucket/cc-pocket-daemon.json` | 基于 1.9.8 的双命令别名候选 |

可从 Git 历史读取原件，例如：

```bash
git show 40de8b56ab8944bdcf114e772898433b5fa16721:packaging/pairlet-candidates/homebrew/Formula/pairlet.rb
```

## 保留的决定

- CLI 使用 `pairlet`，保留 `cc-pocket-daemon`；旧服务、身份和数据目录保持兼容。
- Homebrew 包名迁移与 CLI 别名分开处理；不能同时安装两套会争抢身份的 daemon。
- Scoop 保持 `cc-pocket-daemon` 安装身份；正式配置已包含两个命令。
- 当时未提交 Homebrew 官方 PR，也未完成 Formula 的真实安装、`brew test`、完整 audit、Linux 与旧安装迁移验收。
- Pages 跳转仍由 `scripts/build-legacy-pages-redirects.py` 生成；该工具不依赖已移除的候选目录。

若重新推进包名迁移或官方收录，应从当前正式版本重新生成候选并验证实际安装、服务交接、升级和卸载。本文不延续原任务的授权或待办。
