# syntax=docker/dockerfile:1
# ==============================================================================
# QLToolsV2 镜像 —— 从本仓库自带的 src/ 源码构建（构建期不访问任何代码托管站点）
#
#   源码目录：./src/            源码随本仓库提供
#   许可证  ：Apache License 2.0，见 src/LICENSE（再分发请保留）
#
#   —— 为什么不需要 Node.js ——
#   src/web/embed.go 用 //go:embed all:dist 把前端产物 src/web/dist 编译进
#   二进制，而 web/dist 已随源码一并提供（160 个文件）。所以这里只需 Go
#   编译器，既不需要 Node，也不需要单独拷贝静态资源。
#
#   —— 联网需求 ——
#   仅 Go 模块下载需要网络（国内走 goproxy.cn）。
#   若需彻底离线，见 DEPLOY.md「完全离线 / 内网部署」。
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1 / builder：编译
# ------------------------------------------------------------------------------
FROM golang:1.24-bookworm AS builder

# 国内网络建议 goproxy.cn；海外可传 --build-arg GOPROXY=https://proxy.golang.org,direct
ARG GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct
ARG TZ=Asia/Shanghai

# mattn/go-sqlite3 依赖 CGO，官方 golang 镜像自带 gcc，保持开启。
# GOTOOLCHAIN=auto：go.mod 声明了 toolchain go1.24.3，若镜像内 Go 版本偏低
# 会自动拉取匹配工具链，避免 "go.mod requires go >= 1.24.3" 的构建失败。
ENV CGO_ENABLED=1 \
    GOPROXY=${GOPROXY} \
    GOTOOLCHAIN=auto \
    TZ=${TZ}

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone

WORKDIR /src

# 源码全部取自构建上下文内的 src/（其无关文件由根目录 .dockerignore 排除）
COPY src/ /src/

# 入口包为 ./cmd（cmd/main.go -> internal/app.Start()）
# 若 src/ 下存在 vendor/ 目录（见 DEPLOY.md「完全离线 / 内网部署」），自动切换为
# -mod=vendor 离线模式，此时整个构建过程不访问任何网络。
RUN if [ -d vendor ]; then \
        echo ">> 检测到 vendor/，使用离线构建模式"; \
        go build -mod=vendor -trimpath -ldflags="-s -w" -o /out/QLToolsV2 ./cmd; \
    else \
        echo ">> 通过模块代理下载依赖"; \
        go mod download \
        && go build -trimpath -ldflags="-s -w" -o /out/QLToolsV2 ./cmd; \
    fi

# ------------------------------------------------------------------------------
# Stage 2 / runtime：极简运行镜像
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

ARG TZ=Asia/Shanghai

# 下列 ENV 会被 /app/entrypoint.sh 读取，用于在容器启动时生成
# /app/configs/config.yaml（程序读不到配置文件会直接 panic）
ENV TZ=${TZ} \
    APP_MODE=release \
    APP_ADDRESS=0.0.0.0 \
    APP_PORT=1500 \
    APP_SECRET=QLToolsV2 \
    DB_TYPE=sqlite \
    DB_NAME=/app/data/ql_tools_v2.db \
    CONFIG_PATH=/app/configs/config.yaml \
    KEEP_CONFIG=0

# wget 用于健康检查（/ping 返回 "pong"），bash 供 entrypoint 使用，
# tzdata 让 TZ 生效，ca-certificates 用于访问青龙面板的 HTTPS 接口
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates tzdata wget bash \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone

WORKDIR /app

COPY --from=builder /out/QLToolsV2 /app/QLToolsV2
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/QLToolsV2 /app/entrypoint.sh \
    && mkdir -p /app/data /app/configs

EXPOSE 1500
# SQLite 方案下数据库文件落在 /app/data，务必挂卷持久化
VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
    CMD wget -qO- http://127.0.0.1:${APP_PORT}/ping || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
