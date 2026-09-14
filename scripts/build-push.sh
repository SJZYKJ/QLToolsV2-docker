#!/usr/bin/env bash
# ==============================================================================
# 构建 QLToolsV2 镜像，并（可选）推送到你自己的 Docker Hub
#
#   ./scripts/build-push.sh                            # 只构建，用 .env 里的标签
#   ./scripts/build-push.sh --push                     # 构建并推送
#   ./scripts/build-push.sh --tag 1.0.0 --push         # 指定标签
#   ./scripts/build-push.sh --platforms linux/amd64,linux/arm64 --push
#   DRY_RUN=1 ./scripts/build-push.sh --push           # 只打印命令，不执行
#
#   变量优先取环境变量，其次自动读取同目录 .env：
#     IMAGE_REPO   镜像仓库，例如 yourname/qltoolsv2
#     IMAGE_TAG    镜像标签，默认 latest
#     PLATFORMS    多架构，例如 linux/amd64,linux/arm64（一填就强制推送）
#     GOPROXY      Go 模块代理，默认 https://goproxy.cn,https://proxy.golang.org,direct
# ==============================================================================
set -euo pipefail

PUSH=0
NO_CACHE=0
PLATFORMS_OVERRIDE=""
TAG_OVERRIDE=""

usage() {
  cat <<'HELP'
用法：./scripts/build-push.sh [选项]

  --push                构建完成后推送到镜像仓库
  --tag <标签>          覆盖 IMAGE_TAG
  --platforms <列表>    多架构构建，如 linux/amd64,linux/arm64（必须配合 --push）
  --no-cache            不使用构建缓存
  -h, --help            显示本帮助

环境变量 DRY_RUN=1 时只打印将要执行的命令。
HELP
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --push)      PUSH=1; shift ;;
    --no-cache)  NO_CACHE=1; shift ;;
    --tag)       TAG_OVERRIDE="${2:?--tag 需要一个参数}"; shift 2 ;;
    --platforms) PLATFORMS_OVERRIDE="${2:?--platforms 需要一个参数}"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "未知参数：$1（用 --help 查看用法）" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 从 .env 读取变量（不覆盖已存在的环境变量）
read_env() {
  local key="$1" file="$ROOT/.env" line=""
  [ -f "$file" ] || return 0
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | tail -n 1 || true)"
  [ -n "$line" ] || return 0
  line="${line#*=}"
  line="$(printf '%s' "$line" | tr -d '\r' | sed -E 's/[[:space:]]+$//')"
  case "$line" in
    \"*\") line="${line#\"}"; line="${line%\"}" ;;
    \'*\') line="${line#\'}"; line="${line%\'}" ;;
  esac
  printf '%s' "$line"
}

IMAGE_REPO="${IMAGE_REPO:-$(read_env IMAGE_REPO)}"
IMAGE_TAG="${IMAGE_TAG:-$(read_env IMAGE_TAG)}"
PLATFORMS="${PLATFORMS:-$(read_env PLATFORMS)}"
GOPROXY="${GOPROXY:-$(read_env GOPROXY)}"

[ -n "$TAG_OVERRIDE" ] && IMAGE_TAG="$TAG_OVERRIDE"
[ -n "$PLATFORMS_OVERRIDE" ] && PLATFORMS="$PLATFORMS_OVERRIDE"
[ -n "$IMAGE_TAG" ] || IMAGE_TAG="latest"
[ -n "$GOPROXY" ] || GOPROXY="https://goproxy.cn,https://proxy.golang.org,direct"
DRY_RUN="${DRY_RUN:-0}"

echo "==================================================================="
echo " QLToolsV2 镜像构建"
echo "==================================================================="

# dry-run 只打印命令，不要求本机装 Docker
if [ "$DRY_RUN" != "1" ]; then
  command -v docker >/dev/null 2>&1 || { echo "!! 未找到 docker 命令，请先安装 Docker" >&2; exit 1; }
fi

# 源码检查
if [ ! -f upstream/go.mod ]; then
  echo "!! 缺少内嵌源码 upstream/go.mod" >&2
  echo "   请先执行：./scripts/fetch-upstream.sh" >&2
  echo "   （如果上游已不可访问，请用 --from 指定一个本地源码包）" >&2
  exit 1
fi
if [ ! -d upstream/web/dist ] || [ "$(find upstream/web/dist -type f 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
  echo "!! 警告：upstream/web/dist 为空，成品镜像可能没有前端界面" >&2
fi

if [ -z "$IMAGE_REPO" ]; then
  IMAGE_REPO="qltoolsv2"
  echo ">> 未设置 IMAGE_REPO，使用本地镜像名：${IMAGE_REPO}"
  [ "$PUSH" = "1" ] && { echo "!! --push 需要先在 .env 里设置 IMAGE_REPO=你的用户名/qltoolsv2" >&2; exit 1; }
fi

echo "   源码      ：upstream/  $( [ -f upstream/.upstream-rev ] && grep -E '^resolved=' upstream/.upstream-rev | cut -d= -f2 || echo '(未记录版本)' )"
echo "   镜像      ：${IMAGE_REPO}:${IMAGE_TAG}"
echo "   平台      ：${PLATFORMS:-当前平台}"
echo "   GOPROXY   ：${GOPROXY}"
echo "   推送      ：$([ "$PUSH" = "1" ] && echo 是 || echo 否)"
echo "==================================================================="
echo

DATE_TAG="$(date +%Y%m%d)"
IMAGE_LIST=("${IMAGE_REPO}:${IMAGE_TAG}")
if [ "$PUSH" = "1" ] && [ "$IMAGE_TAG" != "$DATE_TAG" ]; then
  IMAGE_LIST+=("${IMAGE_REPO}:${DATE_TAG}")
fi

TAG_ARGS=()
for img in "${IMAGE_LIST[@]}"; do TAG_ARGS+=(-t "$img"); done

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '   [dry-run] %s\n' "$*"
  else
    printf '>> %s\n' "$*"
    "$@"
  fi
}

if [ -n "$PLATFORMS" ]; then
  # 多架构必须用 buildx，且结果只能推送（无法 load 到本地）
  if [ "$PUSH" != "1" ]; then
    echo "!! 指定了 --platforms，多架构构建必须配合 --push（本地无法加载多架构镜像）" >&2
    exit 1
  fi
  ARGS=(buildx build --platform "$PLATFORMS" --file Dockerfile)
  ARGS+=("${TAG_ARGS[@]}")
  ARGS+=(--build-arg "GOPROXY=${GOPROXY}")
  [ "$NO_CACHE" = "1" ] && ARGS+=(--no-cache)
  ARGS+=(--push .)
  run docker "${ARGS[@]}"
else
  ARGS=(build --file Dockerfile)
  ARGS+=("${TAG_ARGS[@]}")
  ARGS+=(--build-arg "GOPROXY=${GOPROXY}")
  [ "$NO_CACHE" = "1" ] && ARGS+=(--no-cache)
  ARGS+=(.)
  run docker "${ARGS[@]}"

  if [ "$PUSH" = "1" ]; then
    for img in "${IMAGE_LIST[@]}"; do
      run docker push "$img"
    done
  fi
fi

echo
echo "==================================================================="
if [ "$DRY_RUN" = "1" ]; then
  echo " [dry-run] 未实际执行任何命令"
elif [ "$PUSH" = "1" ]; then
  echo " 完成：镜像已推送"
  for img in "${IMAGE_LIST[@]}"; do echo "   - $img"; done
  echo
  echo " 部署端只需在 .env 里填："
  echo "   IMAGE_REPO=${IMAGE_REPO}"
  echo "   IMAGE_TAG=${IMAGE_TAG}"
  echo " 然后执行：./scripts/deploy.sh"
else
  echo " 完成：镜像已构建（未推送）"
  echo "   本地镜像：${IMAGE_REPO}:${IMAGE_TAG}"
  echo
  echo " 需要发布到 Docker Hub 时："
  echo "   docker login"
  echo "   ./scripts/build-push.sh --push"
fi
echo "==================================================================="
