#!/usr/bin/env bash
# 上游变更检测：把「yt-dlp 官方最新 release」与「iawia002/lux 默认分支 HEAD」同
# 「已发布清单」（latest release 里的 downloader-versions.json）比较，决定是否需要
# 构建并重发 release。上游没变就不构建、不发布，下游（应用内更新检测、GitCode 镜像
# 同步）也就不会看到任何变化。
#
# 比较口径（均记录在清单里，见 build-manifest.mjs）：
#   yt-dlp ← engines["yt-dlp"].version   （= 官方 tag，去掉前导 v）
#   lux    ← engines.lux.commit          （= 构建所用的上游完整 commit sha）
#
# 失败策略（宁可红灯，也不要「默认重发」）：
#   - 取不到上游信息 / 已发布清单（网络错误、非 404 的 HTTP 状态）→ 直接失败，等下次定时重试；
#   - 已发布清单不存在（404）或没有 lux.commit（升级到本机制后的第一次）→ 视为有变化，
#     构建一次后即进入稳态。
#
# 输出（写入 $GITHUB_OUTPUT；未设置时只打印到 stdout）：
#   changed=true|false  ytdlp_tag=<上游最新 tag>  lux_sha=<上游 HEAD 完整 sha>
#   lux_date=<该 lux 提交的 UTC 日期 YYYY.MM.DD>  reason=<人类可读原因>
#
# 环境变量（均可选，除 GH_TOKEN 外多用于本地测试）：
#   FORCE=1                   忽略比较结果，强制 changed=true
#   GH_TOKEN                  调 GitHub API（Actions 内由 secrets.GITHUB_TOKEN 注入；本地可用 gh 登录态）
#   PUBLISHED_MANIFEST_FILE   从本地文件读取「已发布清单」
#   PUBLISHED_MANIFEST_URL    覆盖「已发布清单」地址
#   YTDLP_REPO / LUX_REPO     覆盖上游仓库（默认 yt-dlp/yt-dlp、iawia002/lux）
set -euo pipefail

SELF_REPO="${GITHUB_REPOSITORY:-buxuku/smartsub-downloaders}"
YTDLP_REPO="${YTDLP_REPO:-yt-dlp/yt-dlp}"
LUX_REPO="${LUX_REPO:-iawia002/lux}"
MANIFEST_URL="${PUBLISHED_MANIFEST_URL:-https://github.com/${SELF_REPO}/releases/download/latest/downloader-versions.json}"

fail() { echo "check-upstream: $*" >&2; exit 1; }

# --- 1) 上游当前状态 ---------------------------------------------------------
ytdlp_tag="$(gh api "repos/${YTDLP_REPO}/releases/latest" --jq .tag_name)"
{ [ -n "$ytdlp_tag" ] && [ "$ytdlp_tag" != "null" ]; } || fail "取不到 ${YTDLP_REPO} 的最新 release tag"
ytdlp_version="${ytdlp_tag#v}"

IFS=$'\t' read -r lux_sha lux_iso < <(gh api "repos/${LUX_REPO}/commits/HEAD" --jq '[.sha, .commit.committer.date] | @tsv') \
  || fail "取不到 ${LUX_REPO} 的 HEAD 提交"
[[ "$lux_sha" =~ ^[0-9a-f]{40}$ ]] || fail "lux HEAD sha 异常: '${lux_sha}'"
[[ "$lux_iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || fail "lux 提交时间异常: '${lux_iso}'"
# GitHub API 的 committer.date 为 UTC（...Z），直接截取日期部分，避免 GNU/BSD date 差异。
lux_date="${lux_iso%%T*}"
lux_date="${lux_date//-/.}"

# --- 2) 已发布清单（FORCE=1 时无需读取）--------------------------------------
published=""
if [ "${FORCE:-0}" != "1" ]; then
  if [ -n "${PUBLISHED_MANIFEST_FILE:-}" ]; then
    published="$(cat "$PUBLISHED_MANIFEST_FILE")" || fail "读取 ${PUBLISHED_MANIFEST_FILE} 失败"
  else
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    http="$(curl -sSL --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 60 \
      -o "$tmp" -w '%{http_code}' "$MANIFEST_URL")" || fail "无法获取已发布清单: ${MANIFEST_URL}"
    case "$http" in
      200) published="$(cat "$tmp")" ;;
      404) published="" ;; # 尚未发布过
      *) fail "获取已发布清单返回 HTTP ${http}: ${MANIFEST_URL}" ;;
    esac
  fi
  if [ -n "$published" ]; then
    jq -e . >/dev/null 2>&1 <<<"$published" || fail "已发布清单不是合法 JSON"
  fi
fi

# --- 3) 比较 ----------------------------------------------------------------
changed=false
reasons=()
pub_ytdlp="-"
pub_lux="-"

if [ "${FORCE:-0}" = "1" ]; then
  changed=true
  reasons+=("手动强制重建 (force)")
elif [ -z "$published" ]; then
  changed=true
  reasons+=("尚无已发布清单（首次发布）")
else
  pub_ytdlp="$(jq -r '.engines["yt-dlp"].version // ""' <<<"$published")"
  pub_ytdlp="${pub_ytdlp#v}"
  pub_lux_full="$(jq -r '.engines.lux.commit // ""' <<<"$published")"
  pub_lux="${pub_lux_full:0:7}"
  if [ "$pub_ytdlp" != "$ytdlp_version" ]; then
    changed=true
    reasons+=("yt-dlp ${pub_ytdlp:-未知} -> ${ytdlp_version}")
  fi
  if [ "$pub_lux_full" != "$lux_sha" ]; then
    changed=true
    reasons+=("lux ${pub_lux:-未记录 commit} -> ${lux_sha:0:7}")
  fi
  pub_ytdlp="${pub_ytdlp:--}"
  pub_lux="${pub_lux:--}"
fi

if [ "$changed" = true ]; then
  reason=""
  for r in "${reasons[@]}"; do reason="${reason:+${reason}; }${r}"; done
else
  reason="上游无变化 (yt-dlp ${ytdlp_version}, lux ${lux_sha:0:7} @ ${lux_date})，跳过构建与发布"
fi

# --- 4) 输出 ----------------------------------------------------------------
emit() {
  echo "$1=$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "$1=$2" >> "$GITHUB_OUTPUT"; fi
}
emit changed "$changed"
emit ytdlp_tag "$ytdlp_tag"
emit lux_sha "$lux_sha"
emit lux_date "$lux_date"
emit reason "$reason"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### 上游检查"
    echo
    echo "| 组件 | 上游最新 | 已发布 |"
    echo "| --- | --- | --- |"
    echo "| yt-dlp | \`${ytdlp_version}\` | \`${pub_ytdlp}\` |"
    echo "| lux (master) | \`${lux_sha:0:7}\` (${lux_date}) | \`${pub_lux}\` |"
    echo
    if [ "$changed" = true ]; then echo "**需要构建并发布**：${reason}"; else echo "**${reason}**"; fi
  } >> "$GITHUB_STEP_SUMMARY"
fi
