# QLToolsV2 · Docker 部署（提交环境变量到青龙面板）

基于上游 [nuanxinqing123/QLToolsV2](https://github.com/nuanxinqing123/QLToolsV2) 的
**自包含 Docker 部署方案** —— 上游源码已内嵌到 `upstream/`，
**构建不再依赖上游仓库是否存活**，并且支持一键部署与推送到自己的 Docker Hub。

QLToolsV2 是「青龙面板的环境变量第三方提交 / 管理中间件」（Go + Gin + Ent ORM）。
它把外部提交的环境变量，按「变量 → 面板」的绑定关系，**自动轮询分发写入一台或多台
青龙面板的 `/open/envs`**。

> 上游仓库**没有 Dockerfile**（其 CI 引用了 `./Dockerfile` 但文件并不存在），
> 且项目已废弃。本目录补齐了完整可用的构建与编排文件，并把源码锁定内嵌。
>
> **完整说明见 [DEPLOY.md](DEPLOY.md)** ｜ **上游来源与许可证见 [UPSTREAM.md](UPSTREAM.md)**

---

## 快速开始

### 情况一：本机已经装了 Docker

```bash
./scripts/deploy.sh
```

脚本会自动生成 `.env`（含随机 `APP_SECRET`）、构建镜像、启动容器、等待健康检查，
最后打印访问地址。首次构建约需几分钟（下载 Go 依赖）。

### 情况二：本机没有 Docker（Windows 上很常见）→ 走云端构建

**不用装 Docker、不用 WSL2、不用重启系统。** 把本目录推到一个 GitHub 仓库，
在仓库 `Settings → Secrets and variables → Actions` 里加两个 Secret：

| 名称 | 值 |
|------|-----|
| `DOCKERHUB_USERNAME` | 你的 Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | 在 https://hub.docker.com/settings/security 生成的 Access Token（不要用账号密码） |

然后到仓库 `Actions` 页面点 `Run workflow`，几分钟后镜像就出现在 Docker Hub 上了。
之后在任何机器上把 `.env` 里的 `IMAGE_REPO` 填成 `你的用户名/qltoolsv2`，
执行 `./scripts/deploy.sh` 即可一键部署。

**一条命令做完（本机没装 Git 时尤其推荐）**——建仓库、推送、写 Secret、触发构建全自动：

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxx     # GitHub 令牌，需 repo + workflow 权限
export DOCKERHUB_USERNAME=你的用户名
export DOCKERHUB_TOKEN=dckr_pat_xxxxxxxx
./scripts/github-bootstrap.sh
```

详细步骤与原理见 [DEPLOY.md](DEPLOY.md) 的「路线 A」。

> **✅ 本方案已完成一次真实云端构建**（2026-09-14）：
> 镜像 `chungg/qltoolsv2:latest`，摘要 `sha256:0eee0923f16a...`，平台 `linux/amd64`，
> 构建日志 https://github.com/SJZYKJ/QLToolsV2-docker/actions/runs/34829239577
>
> 部署端直接用它即可（`.env` 里已默认填好 `IMAGE_REPO=chungg/qltoolsv2`）：
>
> ```bash
> ./scripts/deploy.sh --pull
> ```

验证：

```bash
curl http://127.0.0.1:1500/ping    # 期望: pong
```

然后打开 `http://<服务器IP>:1500`。

<details>
<summary>不使用脚本的等价手工命令</summary>

```bash
cp .env.example .env      # 至少改掉 APP_SECRET
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```
</details>

---

## 三种部署方式

### 1. 本地一键部署

```bash
./scripts/deploy.sh                    # SQLite（默认）
./scripts/deploy.sh mysql              # 应用 + MySQL 8
./scripts/deploy.sh postgres           # 应用 + PostgreSQL 16
./scripts/deploy.sh --pull             # 强制拉镜像（不构建）
./scripts/deploy.sh --build            # 强制本地源码构建
```

### 2. 构建并推送到自己的 Docker Hub

推一次，之后所有部署端都不再需要源码和编译。

```bash
docker login
# 编辑 .env：IMAGE_REPO=你的用户名/qltoolsv2
./scripts/build-push.sh --push

# 多架构（amd64 + arm64）
./scripts/build-push.sh --platforms linux/amd64,linux/arm64 --push
```

推送后，部署端只要 `.env` 里填了 `IMAGE_REPO`，`./scripts/deploy.sh` 就会自动拉取镜像启动。

### 3. 完全离线 / 内网

```bash
# 导出镜像搬运
./scripts/build-push.sh
docker save qltoolsv2:latest -o qltoolsv2.tar
# 内网机器
docker load -i qltoolsv2.tar && ./scripts/deploy.sh

# 若连 Go 模块代理都不能访问，先生成 vendor/（构建将不再联网）
docker run --rm -v "$PWD/upstream:/src" -w /src golang:1.24-bookworm \
  sh -c 'go mod download && go mod vendor'
```

---

## 目录结构

```
QLToolsV2-docker/
├── upstream/                       # ★ 内嵌上游源码（锁定提交，含前端产物）
├── scripts/
│   ├── deploy.sh                   # 一键部署
│   ├── build-push.sh               # 构建 + 推送自有镜像
│   └── fetch-upstream.sh           # 更新上游源码（唯一需要访问上游的入口）
├── Dockerfile                      # 从 upstream/ 编译，运行期 debian-slim
├── entrypoint.sh                   # 生成 config.yaml；等待数据库就绪后启动
├── docker-compose.yml              # SQLite（零外部依赖）
├── docker-compose.mysql.yml        # 应用 + MySQL 8
├── docker-compose.postgres.yml     # 应用 + PostgreSQL 16
├── docker-compose.build.yml        # 本地构建 override
├── .env.example                    # 环境变量样例
├── UPSTREAM.md                     # 上游来源、锁定提交、许可证
├── DEPLOY.md                       # ★ 部署手册
└── examples/                       # 提交数据的两条示例
```

---

## 跑起来之后要做的事

### 1) 首次注册管理员

**系统只允许注册一个账号，首个注册者即为管理员。** 注册需填图形验证码（算术题）。

### 2) 准备青龙 Open API 凭证

青龙面板 → **系统设置 → 应用设置 → 新建应用** → 拿到 `client_id` / `client_secret`。

### 3) 在 QLTools 后台配置

- **面板管理 → 新增面板**：填青龙地址（如 `http://1.2.3.4:5700`）+ `client_id` + `client_secret`。
- **变量管理 → 新增变量**：填变量名（如 `JD_COOKIE`）、`quantity`、`mode`、`cdk_limit`
  （必填，不启用卡密填 `0`；是否启用 KEY 校验看 `enable_key`）。
- 在变量详情里**绑定到已启用的面板**，并确认变量本身是启用状态。

### 4) 提交数据

```bash
# 公开接口，免登录（注意有 2 req/s 限速）
ENV_ID=1 VALUE="pt_key=xxx;pt_pin=yyy;" \
QLTOOLS_URL=http://127.0.0.1:1500 \
  bash examples/submit.sh
```

一键脚本（自动完成「建面板 → 建变量 → 绑定 → 提交」）：

```bash
QLTOOLS_URL=http://127.0.0.1:1500 \
QLTOOLS_USERNAME=admin QLTOOLS_PASSWORD='你的密码' \
QL_PANEL_URL=http://1.2.3.4:5700 \
QL_CLIENT_ID=xxx QL_CLIENT_SECRET=yyy \
ENV_VALUE="pt_key=xxx;pt_pin=yyy;" \
  python3 examples/submit_to_qinglong.py
```

返回 `data.submitted_to` 即成功写入的青龙面板数量。

---

## 需要知道的几件事

- **源码已内嵌**：`upstream/` 锁定在上游某个具体提交，构建可复现，且与上游是否存活无关。
- **上游是 Apache-2.0**，允许再分发；推送到你自己的 Docker Hub 是合规的。
- **响应体统一为** `{"code": 20000, "msg": "Success", "data": {...}}`，成功码是 **20000**。
- **`APP_ADDRESS` 实际不生效**：上游 HTTP 服务只用 `port`，容器内始终监听 `0.0.0.0`。
- **不需要 Redis**：缓存是进程内 `gcache`，`config.yaml` 里的 `cache` 段不生效。
- **不需要 Node.js**：前端已通过 `//go:embed all:dist` 打进二进制。
- **PostgreSQL 的 `DB_CONFIG` 必须用 libpq 风格**（如 `sslmode=disable`），
  不能沿用 MySQL 的 `charset=utf8mb4&...`。
- **脚本必须是 LF 换行**，CRLF 会导致容器启动即失败。

更多细节与排错见 **[DEPLOY.md](DEPLOY.md)**。
