#!/usr/bin/env bash
# ==============================================================================
# 更新内嵌的上游源码（upstream/）
#
#   ./scripts/fetch-upstream.sh                     # 拉取 master 最新
#   ./scripts/fetch-upstream.sh --ref v1.2.3        # 指定分支或 tag
#   ./scripts/fetch-upstream.sh --sha <commit>      # 锁定到具体提交（推荐）
#   ./scripts/fetch-upstream.sh --from pkg.tar.gz   # 使用本地离线包（无网络）
#   ./scripts/fetch-upstream.sh --backup            # 覆盖前先备份旧源码
#
#   ★ 这是整套方案里【唯一】需要访问上游的脚本。
#     日常构建（build-push.sh）与部署（deploy.sh）都不需要它。
# ==============================================================================
set -euo pipefail

DEFAULT_REPO="https://github.com/nuanxinqing123/QLToolsV2"

REF="master"
SHA=""
LOCAL_TARBALL=""
REPO_URL="$DEFAULT_REPO"
KEEP_BACKUP=0

usage() {
  cat <<'HELP'
用法：./scripts/fetch-upstream.sh [选项]

  --ref <分支|tag>     拉取指定分支或标签（默认 master）
  --sha <commit>       锁定到具体提交，构建可复现（推荐）
  --repo <url>         使用其他上游仓库地址
  --from <tgz 路径>    改用本地离线包，不联网
  --backup             覆盖前把旧 upstream/ 备份为 upstream.bak.<时间戳>
  -h, --help           显示本帮助

示例：
  ./scripts/fetch-upstream.sh
  ./scripts/fetch-upstream.sh --sha 00d5328881ac0e7ef8bc13842979a028b5a8c910
HELP
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)    REF="${2:?--ref 需要一个参数}"; shift 2 ;;
    --sha)    SHA="${2:?--sha 需要一个参数}"; shift 2 ;;
    --repo)   REPO_URL="${2:?--repo 需要一个参数}"; shift 2 ;;
    --from)   LOCAL_TARBALL="${2:?--from 需要一个参数}"; shift 2 ;;
    --backup) KEEP_BACKUP=1; shift ;;
    -h|--help) usage ;;
    *) echo "未知参数：$1（用 --help 查看用法）" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v tar >/dev/null 2>&1 || { echo "!! 需要 tar，请先安装" >&2; exit 1; }
if [ -z "$LOCAL_TARBALL" ]; then
  command -v curl >/dev/null 2>&1 || { echo "!! 需要 curl，请先安装（或改用 --from 本地包）" >&2; exit 1; }
fi

# 从 URL 解析出 owner/repo
REPO_PATH="$(printf '%s' "$REPO_URL" | sed -E 's#^https?://github\.com/##; s#\.git$##; s#/+$##')"
[ -n "$REPO_PATH" ] || { echo "!! 无法解析仓库地址：$REPO_URL" >&2; exit 1; }

# 临时目录：优先 mktemp，不可写时回退到项目内
TMP="$(mktemp -d 2>/dev/null || true)"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  TMP="$ROOT/.tmp-fetch"
  rm -rf "$TMP"
  mkdir -p "$TMP"
fi
trap 'rm -rf "$TMP"' EXIT

ARCHIVE="$TMP/upstream.tar.gz"
SELFTEST=0

if [ -n "$LOCAL_TARBALL" ]; then
  [ -f "$LOCAL_TARBALL" ] || { echo "!! 找不到本地包：$LOCAL_TARBALL" >&2; exit 1; }
  cp "$LOCAL_TARBALL" "$ARCHIVE"
  RESOLVED="local:$(basename "$LOCAL_TARBALL")"
  echo ">> 使用本地离线包：$LOCAL_TARBALL"
elif [ -n "$SHA" ]; then
  echo ">> 下载 ${REPO_PATH} @ ${SHA}"
  curl -fsSL -m 900 "https://codeload.github.com/${REPO_PATH}/tar.gz/${SHA}" -o "$ARCHIVE"
  RESOLVED="$SHA"
else
  echo ">> 下载 ${REPO_PATH} 分支 ${REF}"
  curl -fsSL -m 900 "https://codeload.github.com/${REPO_PATH}/tar.gz/refs/heads/${REF}" -o "$ARCHIVE"
  RESOLVED="$REF"
fi

[ -s "$ARCHIVE" ] || { echo "!! 下载内容为空，请检查网络或参数" >&2; exit 1; }

echo ">> 解压并校验"
EXTRACT="$TMP/extract"
mkdir -p "$EXTRACT"
tar -xzf "$ARCHIVE" -C "$EXTRACT" --strip-components=1
[ -f "$EXTRACT/go.mod" ] || { echo "!! 包结构异常：解压后未找到 go.mod" >&2; exit 1; }
[ -f "$EXTRACT/cmd/main.go" ] || { echo "!! 包结构异常：解压后未找到 cmd/main.go" >&2; exit 1; }
FILE_COUNT="$(find "$EXTRACT" -type f 2>/dev/null | wc -l | tr -d ' ')"
DIST_COUNT="$(find "$EXTRACT/web/dist" -type f 2>/dev/null | wc -l | tr -d ' ')"

if [ "$DIST_COUNT" = "0" ]; then
  echo "!! 警告：web/dist 为空，构建出的镜像将没有前端界面" >&2
fi

if [ "$KEEP_BACKUP" = "1" ] && [ -d upstream ]; then
  BAK="upstream.bak.$(date +%Y%m%d%H%M%S)"
  mv upstream "$BAK"
  echo ">> 旧源码已备份为 $BAK"
else
  rm -rf upstream
fi
mv "$EXTRACT" upstream

# 写入版本记录，便于追溯构建来源
{
  echo "repo=${REPO_URL}"
  echo "ref=${REF}"
  echo "resolved=${RESOLVED}"
  echo "fetched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "files=${FILE_COUNT}"
  echo "web_dist_files=${DIST_COUNT}"
  echo "license=Apache-2.0"
} > upstream/.upstream-rev

echo
echo ">> 完成：upstream/ 已更新"
echo "   来源     ：${REPO_URL}"
echo "   版本     ：${RESOLVED}"
echo "   文件总数 ：${FILE_COUNT}（其中前端产物 ${DIST_COUNT} 个）"
echo "   版本记录 ：upstream/.upstream-rev"
echo
echo "   下一步：./scripts/build-push.sh --push   # 重新构建并推送镜像"
