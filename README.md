# smartsub-downloaders

[SmartSub](https://github.com/buxuku/SmartSub) 在线视频下载功能的下载器分发仓。

`latest` rolling release 汇集两类产物，由 CI（`.github/workflows/build.yml`）每周一自动检查上游，**上游有变化才构建并发布**；站点适配失效需要立即推新时可手动 `workflow_dispatch` 触发：

- **yt-dlp**：搬运官方 release 的独立二进制（win x64/arm64、macOS universal、linux x64/arm64），搬运时按官方 `SHA2-256SUMS` 校验。
- **lux**：从 [iawia002/lux](https://github.com/iawia002/lux) master 源码交叉编译（官方二进制发布已停更，代码仍活跃）。构建固定到检查时的 commit，版本号取**该提交的 UTC 提交日期**（`YYYY.MM.DD`，二进制内为 `YYYY.MM.DD-<short sha>`）。同一个 commit 永远是同一个版本号；同一 Go 工具链下构建结果逐字节一致（旧方案取构建日期，同一 commit 每周都产出不同的二进制）。

`downloader-versions.json` 是应用内安装/更新的版本清单（各引擎版本、平台资产名、SHA256、体积），SmartSub 的 `downloaderManager` 按 gitcode → ghproxy → github 顺序回退拉取。

## 触发与门控

每次触发（每周一 04:00 UTC 定时 / 手动 dispatch）都先跑 `check` 作业（`scripts/check-upstream.sh`），把上游现状与**已发布清单**比较：

| 组件 | 上游现状 | 已发布清单中的对应字段 |
| --- | --- | --- |
| yt-dlp | 官方最新 release tag | `engines["yt-dlp"].version` |
| lux | `iawia002/lux` 默认分支 HEAD sha | `engines.lux.commit` |

- **任一项不同** → 才执行 `build` 作业（构建 + 重建 `latest` release）。
- **都相同** → 整个 `build` 作业跳过，release / 清单 / 二进制保持原样。结果：应用内不会出现无意义的「有可用更新」，国内镜像（GitCode）同步脚本检查清单时也判定「无需同步」，不会重传。
- 取不到上游信息或已发布清单（网络错误、非 404 的 HTTP 状态）时 `check` 直接失败（等下次触发重试），**不会**退化成「默认重发」。
- 手动 dispatch 勾选 **force** 可忽略比较强制重建发布（例如修改了本仓流水线后想重新出一版）。
- 已发布清单不存在或没有 `lux.commit`（升级到本机制后的第一次）视为有变化，构建一次后进入稳态。

> lux 版本号随之改为提交日期，可能低于升级前按「构建日期」发布过的版本。应用按日期字符串比较版本，所以已安装较新构建日期版本的用户不会被提示「更新」到较小的版本号；lux 上游出现更新的提交后会正常提示。同一天内的多个提交版本号相同，应用不会区分（lux 提交频率很低，可接受）。

### 防止定时任务被自动停用

GitHub 会在公开仓库 60 天无仓库活动后自动停用其定时 workflow。门控后上游长期无变化时不再产生 release，所以 `check` 作业在定时触发时会调用一次 enable-workflow API（`PUT /actions/workflows/build.yml/enable`）重置计时（不产生提交；尽力而为，失败不影响主流程）。

## 国内镜像

[buxuku1/smartsub-downloaders](https://gitcode.com/buxuku1/smartsub-downloaders)，用 SmartSub 主仓的 `npm run sync:downloaders`（`scripts/sync-gitcode.sh --target downloaders`）在国内机器上同步。该脚本先比较两边清单的 `generatedAt` 并检查镜像文件是否齐全，没变化就直接退出。
