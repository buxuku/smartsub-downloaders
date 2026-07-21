# smartsub-downloaders

[SmartSub](https://github.com/buxuku/SmartSub) 在线视频下载功能的下载器分发仓。

`latest` rolling release 汇集两类产物，由 CI（`.github/workflows/build.yml`）每周一自动发布，站点适配失效时可手动 `workflow_dispatch` 触发推新：

- **yt-dlp**：搬运官方 release 的独立二进制（win x64/arm64、macOS universal、linux x64/arm64），搬运时按官方 `SHA2-256SUMS` 校验。
- **lux**：从 [iawia002/lux](https://github.com/iawia002/lux) master 源码交叉编译（官方二进制发布已停更，代码仍活跃）。版本号取构建日期（`YYYY.MM.DD`）。

`downloader-versions.json` 是应用内安装/更新的版本清单（各引擎版本、平台资产名、SHA256、体积），SmartSub 的 `downloaderManager` 按 gitcode → ghproxy → github 顺序回退拉取。

国内镜像：[buxuku1/smartsub-downloaders](https://gitcode.com/buxuku1/smartsub-downloaders)，用 SmartSub 主仓的 `npm run sync:downloaders`（`scripts/sync-gitcode.sh --target downloaders`）在国内机器上同步。
