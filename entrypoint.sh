#!/usr/bin/env bash
# ==============================================================================
# QLToolsV2 容器入口脚本
#
#   1) 依据环境变量生成 config.yaml
#      —— 程序读不到配置文件会直接 panic（见 src/internal/app/initializer/viper.go），
#         所以这个文件是"必须存在"的，不能省略。
#   2) 使用 MySQL / PostgreSQL 时，先等待数据库端口就绪
#   3) 以 -config 参数启动 QLToolsV2
#      —— 程序支持 -config / -c 两个参数（见 src/internal/app/bootstrap.go）
#
# 环境变量与配置项的对应关系见 DEPLOY.md
# ==============================================================================
set -euo pipefail

CONFIG_FILE="${CONFIG_PATH:-/app/configs/config.yaml}"

# KEEP_CONFIG=1 时，直接沿用外部挂载进来的配置文件，不做覆盖
if [ "${KEEP_CONFIG:-0}" = "1" ] && [ -f "$CONFIG_FILE" ]; then
  echo ">> KEEP_CONFIG=1，沿用已有配置：${CONFIG_FILE}"
else
  mkdir -p "$(dirname "$CONFIG_FILE")"

  APP_MODE="${APP_MODE:-release}"
  APP_ADDRESS="${APP_ADDRESS:-0.0.0.0}"
  APP_PORT="${APP_PORT:-1500}"
  APP_SECRET="${APP_SECRET:-QLToolsV2}"
  DB_TYPE="${DB_TYPE:-sqlite}"

  # ----------------------------------------------------------------------------
  # 按数据库类型归一化连接参数
  # 依据 src/internal/data/client.go 的 DSN 拼装逻辑：
  #   mysql    -> "user:pass@tcp(host:port)/name?config"
  #   postgres -> "host=... port=... user=... password=... dbname=... config"
  #   sqlite   -> name + "?_fk=1"        （只用 name，其余字段全部忽略）
  # ----------------------------------------------------------------------------
  case "$DB_TYPE" in
    sqlite|sqlite3)
      DB_TYPE="sqlite"
      DB_NAME="${DB_NAME:-/app/data/ql_tools_v2.db}"
      # 注意：程序会自行在 name 后追加 "?_fk=1"，所以路径里不能再出现 "?"
      DB_HOST=""
      DB_PORT=0
      DB_USERNAME=""
      DB_PASSWORD=""
      DB_CONFIG=""
      mkdir -p "$(dirname "$DB_NAME")"
      ;;
    mysql)
      DB_NAME="${DB_NAME:-ql_tools_v2}"
      DB_HOST="${DB_HOST:-127.0.0.1}"
      DB_PORT="${DB_PORT:-3306}"
      DB_USERNAME="${DB_USERNAME:-root}"
      DB_PASSWORD="${DB_PASSWORD:-}"
      DB_CONFIG="${DB_CONFIG:-charset=utf8mb4&parseTime=True&loc=Local}"
      ;;
    postgres|postgresql)
      DB_TYPE="postgres"
      DB_NAME="${DB_NAME:-ql_tools_v2}"
      DB_HOST="${DB_HOST:-127.0.0.1}"
      DB_PORT="${DB_PORT:-5432}"
      DB_USERNAME="${DB_USERNAME:-postgres}"
      DB_PASSWORD="${DB_PASSWORD:-}"
      # PostgreSQL 用的是 libpq 风格参数，绝不能沿用 MySQL 的 charset 串，
      # 否则会直接连接失败。内网部署通常用 sslmode=disable。
      DB_CONFIG="${DB_CONFIG:-sslmode=disable}"
      ;;
    *)
      echo "!! 不支持的 DB_TYPE='${DB_TYPE}'，可选值：sqlite / mysql / postgres" >&2
      exit 1
      ;;
  esac

  cat > "$CONFIG_FILE" <<EOF
app:
  mode: "${APP_MODE}"
  address: "${APP_ADDRESS}"
  port: ${APP_PORT}
  secret: "${APP_SECRET}"

db:
  type: "${DB_TYPE}"
  host: "${DB_HOST}"
  port: ${DB_PORT}
  name: "${DB_NAME}"
  username: "${DB_USERNAME}"
  password: "${DB_PASSWORD}"
  config: '${DB_CONFIG}'
  prefix: ""
  singular: true
  max-idle-conns: 10
  max-open-conns: 100
  log-zap: false
  log-level: "info"

# 缓存当前是进程内 gcache（见 src/internal/app/initializer/cache.go），
# 此段不生效，保留仅为兼容配置结构，无需 Redis。
cache:
  host: "127.0.0.1"
  port: 6379
  password: ""
  db: 0
  pool-size: 10
EOF

  echo ">> 已生成配置：${CONFIG_FILE}（db.type=${DB_TYPE}）"
fi

# ------------------------------------------------------------------------------
# 等待外部数据库端口就绪（最多 120 秒）
# ------------------------------------------------------------------------------
if [ "${DB_TYPE:-sqlite}" != "sqlite" ]; then
  echo ">> 等待数据库 ${DB_HOST:-}:${DB_PORT:-} ..."
  db_ready=0
  for _ in $(seq 1 60); do
    if (exec 3<>/dev/tcp/${DB_HOST:-127.0.0.1}/${DB_PORT:-3306}) 2>/dev/null; then
      db_ready=1
      break
    fi
    sleep 2
  done
  if [ "$db_ready" = "1" ]; then
    echo ">> 数据库端口已就绪"
  else
    echo "!! 数据库在 120 秒内未就绪，仍将继续启动（进程自身会报错退出）" >&2
  fi
fi

echo ">> 启动 QLToolsV2 ..."
exec /app/QLToolsV2 -config "$CONFIG_FILE"
