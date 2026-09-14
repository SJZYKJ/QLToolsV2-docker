#!/usr/bin/env bash
# ==============================================================================
# QLToolsV2 一键部署
#
#   ./scripts/deploy.sh                    # SQLite 单容器（默认，最省事）
#   ./scripts/deploy.sh mysql              # 应用 + MySQL 8
#   ./scripts/deploy.sh postgres           # 应用 + PostgreSQL 16
#
#   ./scripts/deploy.sh --pull             # 强制从镜像仓库拉取（不构建）
#   ./scripts/deploy.sh --build            # 强制用本地 upstream 源码构建
#   ./scripts/deploy.sh mysql --no-wait    # 不等待健康检查
#
#   首次运行会自动从 .env.example 生成 .env，并写入随机 APP_SECRET。
#   默认行为（auto）：.env 里填了 IMAGE_REPO 就拉镜像，否则用本地源码构建。
# ==============================================================================
set -euo pipefail

STACK="sqlite"
MODE="auto"
WAIT=1

usage() {
  cat <<'HELP'
用法：./scripts/deploy.sh [sqlite|mysql|postgres] [选项]

  位置参数   数据库方案，默认 sqlite
  --pull     强制从镜像仓库拉取镜像后启动（不构建）
  --build    强制使用本地 upstream 源码构建后启动
  --no-wait  启动后不等待健康检查
  -h, --help 显示本帮助

示例：
  ./scripts/deploy.sh
  ./scripts/deploy.sh mysql --pull
  ./scripts/deploy.sh postgres --build
HELP
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    sqlite|mysql|postgres|postgresql) STACK="$1"; shift ;;
    --pull)    MODE="pull"; shift ;;
    --build)   MODE="build"; shift ;;
    --no-wait) WAIT=0; shift ;;
    -h|--help) usage ;;
    *) echo "未知参数：$1（用 --help 查看用法）" >&2; exit 1 ;;
  esac
done
[ "$STACK" = "postgresql" ] && STACK="postgres"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48
  fi
}

sed_i() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    local expr="$1"; shift
    sed -i '' "$expr" "$@"
  fi
}

echo "==================================================================="
echo " QLToolsV2 一键部署   (stack=${STACK}, mode=${MODE})"
echo "==================================================================="

# ---------------- 1. 环境检查 ----------------
command -v docker >/dev/null 2>&1 || { echo "!! 未找到 docker 命令，请先安装 Docker" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "!! Docker 守护进程未运行，请先启动 Docker" >&2; exit 1; }

if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC=(docker-compose)
else
  echo "!! 未找到 docker compose，请安装 Docker Compose v2 插件" >&2
  exit 1
fi

case "$STACK" in
  sqlite)   COMPOSE_FILE="docker-compose.yml" ;;
  mysql)    COMPOSE_FILE="docker-compose.mysql.yml" ;;
  postgres) COMPOSE_FILE="docker-compose.postgres.yml" ;;
esac
[ -f "$COMPOSE_FILE" ] || { echo "!! 找不到编排文件：$COMPOSE_FILE" >&2; exit 1; }

# ---------------- 2. 准备 .env ----------------
NEW_ENV=0
if [ ! -f .env ]; then
  [ -f .env.example ] || { echo "!! 缺少 .env.example" >&2; exit 1; }
  cp .env.example .env
  SECRET="$(gen_secret)"
  sed_i "s|^APP_SECRET=.*|APP_SECRET=${SECRET}|" .env
  NEW_ENV=1
  echo ">> 已生成 .env，并写入随机 APP_SECRET（48 位）"
fi

# 环境变量优先，其次读 .env（与 build-push.sh 保持一致）
IMAGE_REPO="${IMAGE_REPO:-$(read_env IMAGE_REPO)}"
IMAGE_TAG="${IMAGE_TAG:-$(read_env IMAGE_TAG)}"; [ -n "$IMAGE_TAG" ] || IMAGE_TAG="latest"
HOST_PORT="${HOST_PORT:-$(read_env HOST_PORT)}"; [ -n "$HOST_PORT" ] || HOST_PORT="1500"

# ---------------- 3. 决定拉取还是构建 ----------------
if [ "$MODE" = "auto" ]; then
  if [ -n "$IMAGE_REPO" ]; then MODE="pull"; else MODE="build"; fi
  echo ">> auto 模式判定为：${MODE}"
fi

if [ "$MODE" = "pull" ]; then
  if [ -z "$IMAGE_REPO" ]; then
    echo "!! --pull 需要在 .env 中设置 IMAGE_REPO（例如 yourname/qltoolsv2）" >&2
    exit 1
  fi
  echo ">> 拉取镜像 ${IMAGE_REPO}:${IMAGE_TAG}"
  if ! "${DC[@]}" -f "$COMPOSE_FILE" pull qltools; then
    echo "!! 拉取失败（镜像不存在、未 docker login，或网络不通）" >&2
    if [ -f upstream/go.mod ]; then
      echo ">> 回退为本地源码构建" >&2
      MODE="build"
    else
      echo "!! 本地没有 upstream 源码，无法回退构建。" >&2
      echo "   请检查 IMAGE_REPO，或先执行 ./scripts/fetch-upstream.sh" >&2
      exit 1
    fi
  fi
fi

# ---------------- 4. 启动 ----------------
if [ "$MODE" = "build" ]; then
  [ -f upstream/go.mod ] || {
    echo "!! 缺少内嵌源码 upstream/go.mod" >&2
    echo "   请先执行：./scripts/fetch-upstream.sh" >&2
    exit 1
  }
  [ -f docker-compose.build.yml ] || { echo "!! 缺少 docker-compose.build.yml" >&2; exit 1; }
  echo ">> 使用本地源码构建并启动（首次构建约需数分钟）"
  "${DC[@]}" -f "$COMPOSE_FILE" -f docker-compose.build.yml up -d --build
else
  echo ">> 使用已有镜像启动"
  "${DC[@]}" -f "$COMPOSE_FILE" up -d
fi

# ---------------- 5. 等待健康 ----------------
HEALTHY=0
if [ "$WAIT" = "1" ]; then
  echo ">> 等待容器就绪 ..."
  for _ in $(seq 1 60); do
    ST="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' qltools_v2 2>/dev/null || true)"
    case "$ST" in
      healthy) HEALTHY=1; break ;;
      exited|dead)
        echo "!! 容器已退出，最近日志：" >&2
        "${DC[@]}" -f "$COMPOSE_FILE" logs --tail 40 qltools >&2 || true
        exit 1
        ;;
    esac
    sleep 2
  done
  [ "$HEALTHY" = "1" ] && echo ">> 容器健康检查通过" || echo "!! 等待超时，容器可能仍在启动，请稍后查看日志"
fi

# ---------------- 6. 输出结果 ----------------
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -n "$IP" ] || IP="<服务器IP>"

echo
echo "==================================================================="
echo " 部署完成"
echo "-------------------------------------------------------------------"
echo "   后台地址 ：http://${IP}:${HOST_PORT}"
echo "   健康检查 ：http://${IP}:${HOST_PORT}/ping   （返回 pong 即正常）"
echo "   容器名称 ：qltools_v2"
echo "   编排文件 ：${COMPOSE_FILE}"
echo
echo "   查看日志 ：${DC[*]} -f ${COMPOSE_FILE} logs -f qltools"
echo "   停止服务 ：${DC[*]} -f ${COMPOSE_FILE} down"
echo "-------------------------------------------------------------------"
echo "   注意：系统只允许注册一个账号，首个注册者即为管理员。"
echo "         请立即完成注册，否则接口将保持开放。"
echo "==================================================================="

if [ "$NEW_ENV" = "1" ]; then
  echo
  echo " 提示：.env 已自动生成，内含随机 APP_SECRET。"
  echo "       如使用 mysql / postgres 方案，请务必修改其中的数据库密码！"
fi
