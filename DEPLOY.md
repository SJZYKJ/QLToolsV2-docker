# QLToolsV2 Docker 部署手册

> 本手册覆盖：部署方式、文件清单、依赖清单、环境变量、逐步操作、数据持久化、排错与安全建议。
>
> - 只想快点跑起来 → [README.md](README.md) 的「30 秒部署」
> - 遇到报错 → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 目录

| 章节 | 内容 |
|------|------|
| [一、这是什么](#一这是什么) | 项目定位与能力边界 |
| [二、四种部署方式](#二四种部署方式) | A 拉镜像 / B 云端构建 / C 本地构建 / D 离线内网 |
| [三、文件清单](#三文件清单) | 每个文件干什么、是否必需 |
| [四、目录结构](#四目录结构) | 宿主机与容器内布局 |
| [五、依赖清单](#五依赖清单) | 部署端 / 构建期 / 运行期依赖 |
| [六、环境变量完整说明](#六环境变量完整说明) | 全部变量逐项解释 |
| [七、部署步骤](#七部署步骤) | 从零到能提交数据的完整流程 |
| [八、数据持久化与升级](#八数据持久化与升级) | 备份、换库、升级、回滚 |
| [九、端口与接口速查](#九端口与接口速查) | 路由、响应体约定 |
| [十、实现要点与已知行为](#十实现要点与已知行为) | 容易踩的隐性行为 |
| [十一、排错](#十一排错) | 常见现象速查表 |
| [十二、安全建议](#十二安全建议) | 上线前必做 |

---

## 一、这是什么

**QLToolsV2** 是青龙面板的**环境变量提交 / 管理中间件**（Go + Gin + Ent ORM）。

它做一件事：把外部提交上来的环境变量值，按「变量 → 面板」的绑定关系，
**自动轮询分发并写入一台或多台青龙面板的 `/open/envs`**。

典型的用法是：外部脚本或第三方服务用一条 HTTP 请求把环境变量（如 `JD_COOKIE`）
提交给本服务，本服务再去更新所有绑定的青龙面板，省去逐台面板手工粘贴。

本仓库提供的是**开箱即用的容器化发行版**：

- 镜像已构建并发布（`chungg/qltoolsv2`），部署端**只需拉镜像**即可运行；
- 源码随仓库提供在 `src/`（含已内嵌的前端产物），构建**不依赖任何外部代码托管站点**；
- 运行期**没有额外依赖**——默认用内置 SQLite，不需要 Redis、Node.js 或 Nginx。

---

## 二、四种部署方式

先明确概念：**「构建」**是把源码编译成镜像，**「部署」**是把镜像跑起来。
镜像已发布，所以绝大多数情况下你只需要「部署」。

| 你的情况 | 推荐方式 |
|----------|----------|
| 只想把服务跑起来 | **方式 A · 拉取已发布镜像** ← 推荐 |
| 本机没有 Docker，但要自己改代码重新构建 | 方式 B · 云端构建后推送 |
| 本机有 Docker，且要改代码 | 方式 C · 本机从源码构建 |
| 内网隔离、完全不能联网 | 方式 D · 完全离线 / 内网 |

---

### 方式 A · 拉取已发布镜像（推荐，最简）

**A1. 最简：一条 `docker run`**

```bash
docker run -d --name qltools \
  -p 1500:1500 \
  -v qltools_data:/app/data \
  -e APP_SECRET="$(openssl rand -base64 48)" \
  --restart unless-stopped \
  chungg/qltoolsv2:latest
```

**A2. 推荐：用 compose**

```bash
cp .env.example .env        # 至少改掉 APP_SECRET
docker compose up -d
```

**A3. 用部署脚本（会顺带做环境检查和健康等待）**

```bash
./scripts/deploy.sh --pull
```

脚本会依次完成：检查 Docker → 生成 `.env`（含随机 `APP_SECRET`）→
拉取镜像 → 启动容器 → 等待健康检查 → 打印访问地址。

**验证**：

```bash
curl http://127.0.0.1:1500/ping     # 期望输出 pong
```

<details>
<summary>不使用脚本时的等价手工命令</summary>

```bash
cp .env.example .env
# 改掉 APP_SECRET：openssl rand -base64 48
docker compose up -d
```
</details>

**A4. 服务器上拿不到仓库文件怎么办（`git clone` 失败）**

国内云主机访问 GitHub 常常超时或中断（`Failure when receiving data from the peer`）。
**这不影响部署**——镜像在 Docker Hub 上，不依赖 GitHub。仓库文件按下面任一方式取：

| 方式 | 命令 / 做法 | 适用 |
|------|-------------|------|
| 本地 scp | `scp docker-compose.yml .env.example root@<IP>:/root/QLToolsV2-docker/` | 本地已有仓库，**首选** |
| 镜像加速 | `git clone --depth 1 https://ghfast.top/https://github.com/SJZYKJ/QLToolsV2-docker.git` | 服务器能出网的加速通道 |
| 手工落文件 | 只写 `docker-compose.yml` + `.env` 两个文件即可，内容照抄本手册 | 完全拿不到文件时 |

> **落文件时注意**：从 Markdown 代码块复制会把 ` ```bash ` 围栏一起带进去，
> 导致 `docker compose up -d` 报 `yaml: line 2: mapping values are not allowed in this context`。
> 写完务必校验：`docker compose config >/dev/null && echo "YAML OK"`。
> 详见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 的「3.1 docker-compose up -d 报 yaml 错」。

> 更省事的做法：`docker compose pull && docker compose up -d` 就是全部的更新操作，
> **日常升级完全不需要碰 GitHub**。

---

### 方式 B · 云端构建并推送（本机无需 Docker）

本机没有 Docker（Windows 上很常见）时，借 GitHub Actions 的算力构建，
产物直接推到镜像仓库，之后任何机器都能拉取部署。

**B-0. 一条命令做完（推荐）**

如果本机**没有独立安装 Git**（只有编辑器内置的 Git，PowerShell 里 `git` 报
「无法将"git"项识别为 cmdlet」），或者你不想手动点网页，用下面这个脚本，
它会自动完成「建仓库 → 推送 → 写 Secret → 触发构建」全部四步：

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxx          # GitHub 令牌，需 repo + workflow 权限
export DOCKERHUB_USERNAME=你的用户名
export DOCKERHUB_TOKEN=dckr_pat_xxxxxxxx
./scripts/github-bootstrap.sh
```

GitHub 令牌在 https://github.com/settings/tokens 生成（**Tokens (classic)** →
`Generate new token (classic)` → 勾选 `repo` 和 `workflow` 两个权限）。

> 为什么需要 `workflow` 权限：本仓库包含 `.github/workflows/` 目录，
> 缺少该权限推送时会被 GitHub 拒绝。

脚本可选参数（环境变量）：`GH_OWNER`（默认令牌所属账号）、`GH_REPO`（默认 `QLToolsV2-docker`）、
`GH_VISIBILITY`（默认 `private`）、`SKIP_PUSH=1`、`SKIP_TRIGGER=1`。

**B-1. 手工做法：三步**

1. **推到 GitHub**：把本目录推到一个 GitHub 仓库（私有仓库也可以）
2. **配置凭据**：仓库 `Settings → Secrets and variables → Actions → New repository secret`，新增两个：

   | 名称 | 值 |
   |------|-----|
   | `DOCKERHUB_USERNAME` | 你的镜像仓库用户名 |
   | `DOCKERHUB_TOKEN` | Docker Hub Access Token（**不要用账号密码**） |

3. **触发构建**：仓库 `Actions` 页面 → 选「构建并推送镜像到 Docker Hub」→ `Run workflow`
   （也可以打标签触发：`git tag v1.0 && git push origin v1.0`）

workflow 文件：`.github/workflows/docker-publish.yml`。它会生成 `latest`、
标签名、以及短提交号（`sha-<7位>`）三类标签，后者便于回滚。

> **默认只构建 `linux/amd64`**。部署到 ARM 服务器（部分云主机、树莓派）前，
> 请按文件内注释把 `platforms` 改成 `linux/amd64,linux/arm64` 后重跑。

> **✅ 本项目已完成真实云端构建**
>
> | 项目 | 值 |
> |------|-----|
> | 镜像 | `chungg/qltoolsv2:latest` |
> | 回滚标签 | `chungg/qltoolsv2:sha-a3b9fbf` |
> | 摘要 | `sha256:910c5afa94d9cd7ec17fb6f4a62dcce2c986755cb3e304de4ad32e6635f291d6` |
> | 平台 | `linux/amd64`（**仅此一个平台**） |
> | 构建日志 | https://github.com/SJZYKJ/QLToolsV2-docker/actions/runs/34944068403 |
> | 耗时 | 约 2 分 41 秒 |
> | 对应提交 | `a3b9fbf` feat: 更新模式支持按变量配置「多值分隔符」与「账号字段分隔符」 |

构建完的镜像，按「方式 A」部署即可。

---

### 方式 C · 本机从源码构建部署

源码在 `src/`，本机直接编译并启动：

```bash
./scripts/deploy.sh --build     # 或 ./scripts/deploy.sh mysql --build
```

首次运行会自动生成 `.env` 与随机 `APP_SECRET`，然后构建镜像、启动容器、
等待健康检查通过，最后打印访问地址。**除 Go 模块代理外不访问任何外部站点。**

自己构建后也可以推到自己的镜像仓库，之后部署端就不需要源码了：

```bash
docker login
# 在 .env 里填 IMAGE_REPO=你的用户名/qltoolsv2
./scripts/build-push.sh --push

# 多架构（同时支持 amd64 / arm64）
./scripts/build-push.sh --platforms linux/amd64,linux/arm64 --push
```

---

### 方式 D · 完全离线 / 内网部署

三种递进的做法，按你的隔离程度选择：

**D1. 导出镜像文件搬运（最简单）**

```bash
# 有网机器
docker pull chungg/qltoolsv2:latest
docker save chungg/qltoolsv2:latest -o qltoolsv2.tar
# 拷贝 tar 到内网机器
docker load -i qltoolsv2.tar
./scripts/deploy.sh --pull
```

**D2. 内网自建镜像仓库**

把 `IMAGE_REPO` 指向内网 registry（如 `registry.intra:5000/qltoolsv2`），
`build-push.sh --push` 与 `deploy.sh --pull` 都能直接工作。

**D3. 连带 Go 依赖一起离线（真正零外网构建）**

从源码构建时默认需要访问 Go 模块代理。若连代理也不能访问，先固化依赖：

```bash
# 用容器生成 vendor/，本机无需安装 Go
docker run --rm -v "$PWD/src:/src" -w /src golang:1.24-bookworm \
  sh -c 'go mod download && go mod vendor'
```

> Windows 下若路径转换报错，改用绝对路径并加 `MSYS_NO_PATHCONV=1`，例如：
> `MSYS_NO_PATHCONV=1 docker run --rm -v "D:/path/to/src:/src" ...`

`Dockerfile` 检测到 `src/vendor/` 会自动切到 `-mod=vendor` 离线模式，
此后构建不再访问任何网络。

---

## 三、文件清单

| 文件 / 目录 | 作用 | 是否必需 |
|------|------|----------|
| `src/` | **服务端源码**（306 个文件，含已内嵌的前端产物 `web/dist`）。构建的唯一源码来源 | 构建时必需 |
| `Dockerfile` | 多阶段构建：从 `src/` 编译，运行期用 debian-slim | **必需** |
| `entrypoint.sh` | 按环境变量生成 `config.yaml`、等待数据库就绪、以 `-config` 启动程序 | **必需** |
| `docker-compose.yml` | 默认方案：单容器 + SQLite，零外部依赖 | 三选一 |
| `docker-compose.mysql.yml` | 生产方案 A：应用 + MySQL 8 | 三选一 |
| `docker-compose.postgres.yml` | 生产方案 B：应用 + PostgreSQL 16 | 三选一 |
| `docker-compose.build.yml` | 构建覆盖文件（override），为上面三个补上 `build:` 段 | 本地构建时必需 |
| `scripts/deploy.sh` | **一键部署**：检查环境 → 生成 .env → 拉镜像或本地构建 → 启动 → 等待健康 | **必需** |
| `scripts/build-push.sh` | 构建镜像并（可选）推送到自己的镜像仓库 | 可选 |
| `scripts/github-bootstrap.sh` | 建仓库 → 推送 → 写 Secret → 触发云端构建，一条龙 | 可选 |
| `scripts/gh-set-secret.py` | 上面脚本的辅助程序（GitHub 要求 Secret 加密上传） | 可选 |
| `.github/workflows/docker-publish.yml` | **云端构建**：在 GitHub Actions 上构建并推送，本机无需装 Docker | 可选 |
| `.env.example` | 环境变量样例；`deploy.sh` 会据此自动生成 `.env` | 推荐 |
| `.dockerignore` | 精简构建上下文（**注意：不能排除 `src/` 下的源码与 `web/dist`**） | 推荐 |
| `.gitattributes` | 强制 shell/yaml 用 LF 换行，防止 Windows 检出成 CRLF 破坏容器启动 | 推荐 |
| `.gitignore` | 忽略 `.env` 等敏感与临时文件 | 推荐 |
| `configs/config.yaml` | 配置参考样例（**容器不读它**；配合 `KEEP_CONFIG=1` 可挂载使用） | 参考 |
| `examples/submit.sh` | 用 curl 提交一条数据（公开接口，免登录） | 可选 |
| `examples/submit_to_qinglong.py` | 一键：登录 → 建面板 → 建变量 → 绑定 → 提交 | 可选 |
| `NOTICE.md` | 第三方代码的许可与归属说明 | 推荐 |
| `README.md` | **入口文档**：30 秒部署 + 跑起来之后要做什么 | 推荐 |
| `DEPLOY.md` | 本文，完整部署手册 | 推荐 |
| `TROUBLESHOOTING.md` | **排错手册**：按现象组织，含实战案例 | 推荐 |

---

## 四、目录结构

### 4.1 宿主机（本仓库）

```
QLToolsV2-docker/
├── src/                             # ★ 服务端源码（306 文件）
│   ├── .source-rev                  #   快照记录：版本 / 文件数 / 许可
│   ├── LICENSE                      #   Apache-2.0
│   ├── go.mod / go.sum
│   ├── cmd/  internal/  configs/
│   └── web/dist/                    #   前端产物（158 文件，已被 go:embed）
├── scripts/
│   ├── deploy.sh                    # 一键部署
│   ├── build-push.sh                # 构建 + 推送
│   ├── github-bootstrap.sh          # 云端构建一条龙
│   └── gh-set-secret.py
├── examples/
│   ├── submit.sh
│   └── submit_to_qinglong.py
├── configs/
│   └── config.yaml                  # 配置参考样例
├── Dockerfile
├── docker-compose.yml               # SQLite
├── docker-compose.mysql.yml         # MySQL
├── docker-compose.postgres.yml      # PostgreSQL
├── docker-compose.build.yml         # 构建 override
├── entrypoint.sh
├── .env.example                     # -> cp .env.example .env（deploy.sh 自动做）
├── .dockerignore  .gitattributes  .gitignore
├── README.md                        # 入口：30 秒部署
├── DEPLOY.md                        # 本手册
├── TROUBLESHOOTING.md               # 排错手册
├── NOTICE.md                        # 第三方许可
└── .workbuddy/                      # 工作记录（与部署无关，已在 .dockerignore 中）
```

### 4.2 容器内（镜像运行时）

```
/app
├── QLToolsV2            # 编译好的二进制（构建阶段产出，前端已内嵌）
├── entrypoint.sh        # 入口脚本
├── configs/
│   └── config.yaml      # 每次启动由 entrypoint.sh 生成
└── data/                # 卷挂载点 -> 命名卷 qltools_data
    └── ql_tools_v2.db   # SQLite 模式的数据库文件；MySQL/PG 模式下此目录为空
```

前端资源**不需要目录**：`src/web/embed.go` 用 `//go:embed all:dist` 把
Vue 构建产物打进了二进制，运行期既不需要 Node.js，也不需要拷贝 `web/dist`。

---

## 五、依赖清单

### 5.1 部署端依赖

| 项 | 要求 | 说明 |
|----|------|------|
| Docker Engine | 20.10+（推荐 24+） | 仅方式 C / D3 需要 BuildKit |
| Docker Compose | v2（`docker compose` 子命令） | 不是老的 `docker-compose` v1 |
| 网络 | 能访问镜像仓库 | 只有方式 C 从源码构建时才需要 Go 模块代理 |

**只有拉镜像部署（方式 A）时，除了 Docker 本身什么都不需要。**

### 5.2 基础镜像

| 阶段 | 镜像 | 用途 |
|------|------|------|
| 构建 | `golang:1.24-bookworm` | 编译；自带 gcc，满足 CGO |
| 运行 | `debian:bookworm-slim` | 约 100 MB 级 |
| 数据库 | `mysql:8.0` / `postgres:16-alpine` | 按需，非必需 |

### 5.3 构建期系统包

`git`、`ca-certificates`、`tzdata`

（`git` 只为兼容少数走 VCS 拉取的 Go 模块而保留；源码本身来自构建上下文。）

### 5.4 运行期系统包

`ca-certificates`（访问青龙 HTTPS）、`tzdata`（时区）、`wget`（健康检查）、`bash`（entrypoint）

### 5.5 Go 模块（`src/go.mod`，24 个直接依赖）

工具链声明 `go 1.24.0` + `toolchain go1.24.3`。主要直接依赖：

| 模块 | 版本 | 用途 |
|------|------|------|
| `entgo.io/ent` | v0.14.5 | ORM，负责自动建表迁移 |
| `github.com/gin-gonic/gin` | v1.11.0 | HTTP 框架 |
| `github.com/gin-contrib/cors` | v1.7.6 | 跨域 |
| `github.com/spf13/viper` | v1.21.0 | 读 `config.yaml` |
| `github.com/mattn/go-sqlite3` | v1.14.24 | SQLite 驱动（**需要 CGO**） |
| `github.com/go-sql-driver/mysql` | v1.8.1 | MySQL 驱动 |
| `github.com/lib/pq` | v1.10.9 | PostgreSQL 驱动 |
| `github.com/golang-jwt/jwt/v5` | v5.3.0 | JWT 鉴权 |
| `github.com/mojocn/base64Captcha` | v1.3.8 | 算术验证码 |
| `github.com/bluele/gcache` | v0.0.2 | 进程内缓存（**替代 Redis**） |
| `github.com/dop251/goja` | — | 插件系统用的 JS 引擎 |
| `go.uber.org/zap` | v1.27.1 | 日志 |
| `github.com/swaggo/gin-swagger` | v1.6.1 | Swagger（仅 debug 模式） |
| `github.com/zsais/go-gin-prometheus` | v1.0.2 | `/metrics` |

> **关键结论：运行期不需要 Redis、不需要 Node.js、不需要 Nginx。**
> 缓存是 `gcache` 内存实现，前端是 `go:embed` 进二进制的。
> 唯一的运行期外部依赖是你自己选的数据库（或直接用 SQLite 免掉）。

---

## 六、环境变量完整说明

`entrypoint.sh` 在容器启动时读取这些变量并生成 `/app/configs/config.yaml`。

### 6.1 应用层（写入 `app.*`）

| 环境变量 | 默认值 | 作用 |
|----------|--------|------|
| `TZ` | `Asia/Shanghai` | 时区 |
| `APP_MODE` | `release` | `release` / `debug` / `test`。**debug 才会开放 `/swagger/*any`** |
| `APP_PORT` | `1500` | 容器内监听端口 |
| `APP_ADDRESS` | `0.0.0.0` | **实际不生效**，见下方说明，保留仅为兼容配置结构 |
| `APP_SECRET` | `QLToolsV2` | JWT 签名密钥，**生产必须改**（`deploy.sh` 自动生成随机值） |

> **`APP_ADDRESS` 为什么不生效：** 启动 HTTP 服务时写的是
> `Addr: fmt.Sprintf(":%d", config.Config.App.Port)` —— 只取了 `port`，没有用 `address`
> （见 `src/internal/app/bootstrap.go`）。因此进程在容器内始终监听 `0.0.0.0`，
> 端口映射不受该变量影响。

### 6.2 数据库层（写入 `db.*`）

| 环境变量 | sqlite 默认 | mysql 默认 | postgres 默认 | 说明 |
|----------|-------------|------------|---------------|------|
| `DB_TYPE` | `sqlite` | `mysql` | `postgres` | 也接受 `sqlite3` / `postgresql` |
| `DB_NAME` | `/app/data/ql_tools_v2.db` | `ql_tools_v2` | `ql_tools_v2` | sqlite 时为**文件路径**，其余为库名 |
| `DB_HOST` | — | `127.0.0.1` | `127.0.0.1` | sqlite 忽略 |
| `DB_PORT` | — | `3306` | `5432` | sqlite 忽略 |
| `DB_USERNAME` | — | `root` | `postgres` | sqlite 忽略 |
| `DB_PASSWORD` | — | 空 | 空 | sqlite 忽略 |
| `DB_CONFIG` | 空 | `charset=utf8mb4&parseTime=True&loc=Local` | `sslmode=disable` | **两种数据库格式完全不同** |

### 6.3 镜像与部署（部署端最关键）

| 环境变量 | 默认值 | 作用 |
|----------|--------|------|
| `IMAGE_REPO` | `chungg/qltoolsv2` | 镜像仓库。填了就用镜像，留空则用本地 `src/` 源码构建 |
| `IMAGE_TAG` | `latest` | 镜像标签，也可填 `sha-<7位提交号>` 锁定版本 |
| `PLATFORMS` | 空 | 多架构构建，如 `linux/amd64,linux/arm64` |
| `GOPROXY` | `https://goproxy.cn,https://proxy.golang.org,direct` | Go 模块代理（构建期生效） |

### 6.4 容器行为控制（不写入配置文件）

| 环境变量 | 默认值 | 作用 |
|----------|--------|------|
| `QLTOOLS_ADMIN_USERNAME` | `admin` | 初始管理员用户名。**不写入 `config.yaml`**，由 `src/internal/app/initializer/seed.go` 直接读环境变量 |
| `QLTOOLS_ADMIN_PASSWORD` | 空 | 初始管理员密码。**留空则跳过自动建号**，此时可打开 `/admin` 点「注册账号」自助注册 |
| `QLTOOLS_ADMIN_RESET` | 特殊值，置 `1` | 对**已存在**的同名账号强制重置密码（忘记密码的补救手段）。生效一次后应改回 `0` |
| `CONFIG_PATH` | `/app/configs/config.yaml` | 生成/读取配置文件的位置 |
| `KEEP_CONFIG` | `0` | 设为 `1` 且文件已存在时跳过生成，直接使用挂载进来的配置 |
| `HOST_PORT` | `1500` | 宿主机映射端口（仅 compose 使用） |

### 6.5 Dockerfile 构建参数（`--build-arg`）

| 参数 | 默认值 | 作用 |
|------|--------|------|
| `GOPROXY` | `https://goproxy.cn,https://proxy.golang.org,direct` | Go 模块代理，国内加速 |
| `TZ` | `Asia/Shanghai` | 构建镜像的时区 |

---

## 七、部署步骤

### 步骤 0 · 前置检查

```bash
docker version          # 需要 20.10+
docker compose version  # 需要 v2
```

### 步骤 1 · 启动服务

```bash
./scripts/deploy.sh --pull
```

日志出现 `数据库连接成功 (Ent)` 与 `监听端口: 1500` 即为正常：

```bash
curl http://127.0.0.1:1500/ping     # 期望输出 pong
```

### 步骤 2 · 准备管理员账号（**只在第一次做**）

先记住两个入口：

| 地址 | 页面 | 是否需要登录 |
|------|------|--------------|
| `http://<服务器IP>:1500/` | 免密提交页（重定向到 `/commitVariable`），外部提交数据用 | 不需要 |
| `http://<服务器IP>:1500/admin` | 后台管理员登录页 | 需要账号密码 + 验证码 |

> `/admin` 与 `/login` 指向同一个页面，两个地址都能进后台。

管理员账号有三种拿法，**任选一种**：

**（a）环境变量自动创建（推荐，无人值守部署用这个）**

`.env` 里填：

```ini
QLTOOLS_ADMIN_USERNAME=admin
QLTOOLS_ADMIN_PASSWORD=你的密码
```

容器首次启动时，如果数据库里一个用户都没有，就会用这组账号自动建号，
日志里会出现 `已自动创建管理员账号，可直接用该账号登录后台`。
之后直接打开 `/admin` 登录即可，不需要点「注册账号」。
`./scripts/deploy.sh` 首次生成 `.env` 时会写入一个随机密码并在结尾打印。

**（b）页面自助注册**

打开 `http://<服务器IP>:1500/admin`，点表单下方的 **「注册账号」**，
填用户名、密码、验证码（算术题，点验证码图片刷新）即可。

> **系统只允许注册一个账号，首个注册者即为管理员。**
> 登录页输入框里的「请输入用户名 / 请输入密码」只是占位提示，
> 系统**不会**预置 `admin/admin` 之类的默认账号。

**（c）忘记密码时重置**

`.env` 里填好 `QLTOOLS_ADMIN_PASSWORD`，并把 `QLTOOLS_ADMIN_RESET` 置为 `1`，
重启一次容器（`docker compose up -d`），已存在的同名账号密码会被重置为该值。

> ⚠️ 重置完**必须把 `QLTOOLS_ADMIN_RESET` 改回 `0`**，否则每次重启都会把密码改回去。

登录成功后浏览器会拿到 `access_token`（JWT），后续管理类接口都要带它。

### 步骤 3 · 在青龙面板侧准备 Open API 凭证

青龙面板 → **系统设置 → 应用设置 → 新建应用**，得到 `client_id` 与 `client_secret`。
（这组凭证是 QLTools 连接青龙用的身份，不是青龙的登录账号密码。）

### 步骤 4 · 在 QLTools 后台配置面板与变量

1. **面板管理 → 新增面板**：填青龙地址（如 `http://1.2.3.4:5700`）+ `client_id` + `client_secret`，
   保存时会自动取 token，可点「测试连接」验证。
2. **变量管理 → 新增变量**：填变量名（如 `JD_COOKIE`）、`quantity`（负载数量）、`mode`、
   `cdk_limit`（必填，不启用卡密填 `0`）；**是否启用 KEY 校验由 `enable_key` 控制，不是 `cdk_limit`**。
   - `mode = 新建模式(1)`：每次提交都往面板里新建一条变量。
   - `mode = 更新模式(2)`：把提交值**合并**进同名变量（已有则替换该段、没有则追加）。此模式下会多出三个可选项：
     - **匹配正则[更新]**：从每段里提取「账号标识」用于判重（账号字段分隔符留空时才生效）。
     - **多值分隔符**：多账号之间用什么隔开；**留空表示自动**（原值有换行用换行，否则用 `&`）。
     - **账号字段分隔符**：取每段中第一个该符号**之前**的内容作为账号标识。例如填 `;`，`1;2` 与 `1;5` 会被认定是**同一个账号**（都是 `1`），于是把 `1;2` 改成 `1;5`，而不是追加成 `1;2&1;5`。
3. 在变量详情里**绑定到已启用的面板**，并确认变量本身是「启用」状态。

> 变量与面板只要有一方是禁用状态，提交就会返回 `submitted_to = 0`。

### 步骤 5 · 提交数据

**方式 A —— 后台页面提交**：变量页直接填值提交。

**方式 B —— 公开接口（免登录）**：

```bash
ENV_ID=1 VALUE="pt_key=xxx;pt_pin=yyy;" \
QLTOOLS_URL=http://127.0.0.1:1500 \
  bash examples/submit.sh
```

**方式 C —— 一键脚本（登录 → 建面板 → 建变量 → 绑定 → 提交）**：

```bash
QLTOOLS_URL=http://127.0.0.1:1500 \
QLTOOLS_USERNAME=admin QLTOOLS_PASSWORD='你的密码' \
QL_PANEL_URL=http://1.2.3.4:5700 \
QL_CLIENT_ID=xxx QL_CLIENT_SECRET=yyy \
ENV_NAME=JD_COOKIE ENV_VALUE="pt_key=xxx;pt_pin=yyy;" \
  python3 examples/submit_to_qinglong.py
```

脚本会拉取验证码存成 `captcha.png`，在终端输入答案即可自动登录，无需手工复制 token。
也可以直接给 `QLTOOLS_TOKEN=<access_token>` 跳过验证码环节。

### 步骤 6 · 切换到生产数据库（二选一）

```bash
./scripts/deploy.sh mysql       # 应用 + MySQL 8
./scripts/deploy.sh postgres    # 应用 + PostgreSQL 16
```

数据表由程序在**首次启动时自动迁移创建**，不需要手工执行任何 SQL。
entrypoint 会先等待数据库端口就绪再启动应用。

> 从 SQLite 切到 MySQL/PG 属于**换库**，原 SQLite 里的用户、面板、变量配置不会自动迁移，
> 需要在后台重新配置（或自行导出导入）。

### 步骤 7 · 升级与回滚

见下一节「数据持久化与升级」。

---

## 八、数据持久化与升级

| 部署方式 | 卷 | 内容 |
|----------|----|------|
| SQLite | `qltools_data` → `/app/data` | `ql_tools_v2.db` 数据库文件 |
| MySQL | `qltools_data` + `qltools_mysql_data` | 前者空置，后者是 MySQL 数据目录 |
| PostgreSQL | `qltools_data` + `qltools_postgres_data` | 同上 |

**只要不删卷，数据就不会丢。**

升级：

```bash
docker compose pull && docker compose up -d     # 拉取最新镜像并重建容器
```

回滚：把 `.env` 里的 `IMAGE_TAG` 改成之前构建产出的提交号标签（`sha-<7位提交号>`），
然后 `./scripts/deploy.sh --pull`。

> `docker compose down -v` 会删除所有卷（数据全丢），只在确认不需要数据时使用。

---

## 九、端口与接口速查

| 项 | 值 |
|----|----|
| 服务端口 | `1500` |
| 健康检查 | `GET /ping` → `pong` |
| 免密提交页 | `GET /`（重定向到 `/commitVariable`，**不需要登录**） |
| 后台登录页 | `GET /admin`（等价于 `/login`，需要账号密码 + 验证码） |
| 指标 | `GET /metrics`（Prometheus） |
| Swagger | `GET /swagger/index.html`（**仅 `APP_MODE=debug`**） |
| 统一响应体 | `{"code": 20000, "msg": "Success", "data": {...}}` |
| 成功码 | **20000**，不是 200 / 0 |

> 前端是 Vue Router history 模式，除 `/api/*` 与 `/assets/*` 之外的路径都由
> `initializer/web.go` 的 `NoRoute` 回落到内嵌 `index.html`，所以 `/admin` 这类
> 前端路由由浏览器端接管，服务端不需要单独配置。

| 接口 | 方法 | 鉴权 |
|------|------|------|
| `/api/auth/captcha` | GET | 否 |
| `/api/auth/register` | POST | 否（需验证码） |
| `/api/auth/login` | POST | 否（需验证码） |
| `/api/auth/refresh` | POST | 否（需 refresh_token） |
| `/api/open/submit` | POST | 否，**限速更严（2 req/s，桶容量 5）** |
| `/api/open/services` | GET | 否 |
| `/api/open/slots/{env_id}` | GET | 否 |
| `/api/open/check-cdk` | POST | 否 |
| `/api/panel/*`、`/api/env/*`、`/api/cdk/*`、`/api/plugin/*`、`/api/dashboard/*` | GET/POST/PUT/DELETE | **需 JWT** |

JWT 请求头格式：`Authorization: Bearer <access_token>`

`POST /api/open/submit` 请求体：

```json
{
  "env_id": 1,
  "value": "pt_key=xxx;pt_pin=yyy;",
  "key": "可选，变量启用了 KEY 校验时必填",
  "remarks": "可选备注"
}
```

响应中的 `data.submitted_to` 是**成功写入的青龙面板数量**。

---

## 十、实现要点与已知行为

以下行为与直觉不符，是配置和排错时最容易踩的坑。括号内是 `src/` 中对应的实现位置。

| # | 要点 |
|---|------|
| 1 | 启动参数支持 `-config` 与 `-c`，默认路径是相对的 `configs/config.yaml`（`internal/app/bootstrap.go`、`initializer/viper.go`） |
| 2 | 配置文件读不到会**直接 panic**，所以 entrypoint 必须生成它（`initializer/viper.go`） |
| 3 | **`app.address` 不生效**，HTTP 服务只用 `port`，始终监听全部网卡（`bootstrap.go`） |
| 4 | 前端已 `//go:embed all:dist` 内嵌，**不需要 Node 构建**（`web/embed.go`） |
| 5 | 缓存是进程内 `gcache`，**不需要 Redis**，`cache` 配置段实际不生效（`initializer/cache.go`） |
| 6 | SQLite 只用 `db.name` 作文件路径，并自行追加 `?_fk=1`，**路径中不可含 `?`**（`internal/data/client.go`） |
| 7 | PostgreSQL 的 `db.config` 会**原样拼进 DSN**，必须是 libpq 风格参数（`internal/data/client.go`） |
| 8 | 成功响应码是 **20000**，字段名是 **`msg`** 不是 `message`（`internal/pkg/response/`） |
| 9 | 健康检查 `/ping` 返回 `pong`（`initializer/router.go`） |
| 10 | **注册和登录都必须过验证码**，验证码存内存（`controller/auth.go`） |
| 11 | 系统**只允许注册一个用户**，首个即为管理员 |
| 12 | 启动时若设置了 `QLTOOLS_ADMIN_PASSWORD` 且库中无用户，会**自动建号**；库中已有用户则默认不动，只有 `QLTOOLS_ADMIN_RESET=1` 才重置密码（`initializer/seed.go`） |
| 13 | 前端路由里 `/admin` 是 `/login` 的别名，二者是同一个登录页；`/` 重定向到免密提交页 `/commitVariable`（`web/dist/assets/index-*.js` 内的 `routes`） |
| 14 | 表结构由 Ent 启动时**自动迁移**，无需手工建表（`internal/data/client.go`） |
| 15 | `/api/open/submit` 免登录但限速更严（2 req/s，桶容量 5）（`controller/open.go`） |
| 16 | 鉴权头是 `Authorization: Bearer <token>`，且只接受 access 类型 token（`middleware/jwt.go`） |
| 17 | 变量创建时 `quantity`、`mode`、`cdk_limit` 都是**必填**；新变量默认可能禁用（`internal/schema/env.go`） |
| 18 | 控制 KEY（卡密）校验的是 `enable_key` 字段，不是 `cdk_limit=0`（`internal/schema/env.go`） |
| 19 | 优雅停机有 10 秒超时，compose 里 `stop_grace_period` 设了 15 秒留余量 |
| 20 | **未匹配路由会分流**：非 `/api/` 且不含 `.` 的路径交给前端 `index.html`（SPA history 模式，HTTP 200）；`/api/*` 未匹配则返回 JSON `{"code":50001,"msg":"接口不存在: <方法> <路径>"}`。**API 路径永远不会返回 HTML**（`initializer/web.go`） |
| 21 | 登出接口同时注册了 `POST` 与 `GET /api/auth/logout`；前端产物里用的是 **POST**（`controller/auth.go`） |
| 22 | token 存在进程内 `gcache`，**容器重启即全部失效**，需要重新登录；改 `APP_SECRET` 同理（`internal/utils/jwt.go`） |
| 23 | 变量的「匹配正则」是**提取规则而非校验规则**：`FindString` 取最左匹配的子串，并**用它覆盖整个提交值**。填 `；` 而值输入 `1；2`，最终只会存 `；`。想原样保存要写 `^[\s\S]*$` 这类整体圈定的正则（`internal/service/open.go`，详见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 5.1） |
| 24 | **更新模式是「合并」不是「覆盖」**：同名变量的已有值按「多值分隔符」拆段，用「账号字段分隔符」（留空时退回 `regex_update`）提取账号标识——标识命中就替换该段，都不命中就追加到末尾；合并结果与原文一致时不写回；只有所有面板都没有该变量名才新建（`internal/service/open.go`，详见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 5.2） |
| 25 | 变量新增两个可选字段：**`separator`（多值分隔符）** 与 **`field_separator`（账号字段分隔符）**，各自留空即保持旧行为——`separator` 留空表示自动（原值有换行用换行，否则用 `&`，且两种都算分隔符），`field_separator` 留空表示用 `regex_update` 判重。`separator` 支持 `newline` / `换行` 别名及 `\n`/`\r`/`\t` 转义。旧库升级时 Ent 自动迁移会补上这两个可空列，无需手工建表（`internal/data/ent/schema/env.go`、`internal/service/open.go`） |

---

## 十一、排错

> 下表是速查。**完整版（含排查思路、命令与实战案例）见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。**

| 现象 | 原因与处理 |
|------|------------|
| `!! 拉取失败（镜像不存在、未 docker login…）` | `IMAGE_REPO` 写错或仓库私有未登录。确认仓库名，或改从源码构建（`deploy.sh --build`） |
| 容器起不来，日志报 `fatal error config file` | `config.yaml` 没生成出来，程序读不到配置会直接 panic。检查 `CONFIG_PATH` 指向的目录可写，或 `KEEP_CONFIG=1` 时挂载的文件是否真的存在 |
| 日志报 `failed creating schema resources` | 数据库连不上或权限不足。核对 `DB_HOST/PORT/NAME/USERNAME/PASSWORD`，以及 MySQL 账号是否有建表权限 |
| 用 PostgreSQL 时连接直接失败 | `DB_CONFIG` 沿用了 MySQL 的 charset 串。postgres 需要 libpq 风格，用 `sslmode=disable` |
| `/usr/bin/env: 'bash\r': No such file or directory` | 脚本是 CRLF 换行（Windows 编辑导致）。执行 `sed -i 's/\r$//' entrypoint.sh scripts/*.sh`，并保留仓库内的 `.gitattributes` |
| 提交返回 `submitted_to: 0` | 变量未启用，或绑定的面板处于禁用状态，或青龙 `client_id/secret` 不正确 / 青龙 Open API 没开 |
| 提交返回 `code: 49997`（请求过于频繁） | `/api/open/submit` 有令牌桶限速（2 req/s，容量 5），降低提交频率 |
| 登录报「用户不存在或查询失败」 | 数据库里还没有任何账号。**系统不预置默认账号**。要么在 `.env` 里配 `QLTOOLS_ADMIN_USERNAME/QLTOOLS_ADMIN_PASSWORD` 重启自动建号，要么打开 `/admin` 点「注册账号」注册 |
| 注册提示「系统已存在用户」 | 全系统只允许一个账号。直接登录即可；忘记密码用 `QLTOOLS_ADMIN_RESET=1` 重启重置（见步骤 2），或清库中 `users` 表 |
| 打开 `/admin` 不是登录页 | 确认拉到的镜像是最新的（`docker compose pull`）。`/admin` 是 `login` 路由的别名，旧镜像里没有该别名，会落到 404 页 |
| 验证码一直提示错误 | 验证码用**内存存储**，重启容器会失效，刷新页面重新取即可 |
| 端口 1500 被占用 | 在 `.env` 里改 `HOST_PORT=15001` |
| `no matching manifest for linux/arm64` | 镜像只构建了 amd64。按方式 B 改 `platforms` 后重跑构建 |
| 构建很慢 | 首次要 `go mod download`。确认 `GOPROXY` 用的是 `https://goproxy.cn`；若已做 vendor 可完全离线 |
| 构建报 `requires go >= 1.24.x` | 镜像内 Go 版本偏低。Dockerfile 已设 `GOTOOLCHAIN=auto` 兜底自动拉取匹配工具链 |
| `deploy.sh` 说 Docker 守护进程未运行 | 启动 Docker Desktop / `systemctl start docker` |
| 页面只弹一个光秃秃的 **`Error`**，没有任何信息 | 请求大概率**没匹配到路由**（路径或 HTTP 方法不对）。`NoRoute` 会把未匹配路径交给前端 `index.html`（HTTP 200 + HTML），前端拦截器解析不出 `code` 字段就只弹 `Error`。F12 → Network 看该请求的**状态码与响应体**；若是 HTML 说明是路由问题。已加固：`/api/*` 未匹配时现在返回 `{"code":50001,"msg":"接口不存在: ..."}` |
| 点「退出登录」报 `Error` | 历史 bug：前端用 `POST /api/auth/logout`，后端只注册了 GET。已修复（后端补上 POST）。**拉最新镜像即可**：`docker compose pull && docker compose up -d` |
| `docker compose up -d` 报 `yaml: line 2: mapping values are not allowed in this context` | `docker-compose.yml` 第 1 行不是 `services:`，多半是复制代码块时把 ` ```bash ` 围栏一起粘进去了。`head -5` 确认后用 `docker compose config` 校验 |
| 改了 `.env` 但容器里没生效 | `.env` 只是 compose 的**变量替换源**，变量必须在 compose 的 `environment:` 里显式映射；且要 `docker compose up -d` 重建容器。用 `docker exec <容器> env \| grep QLTOOLS` 确认 |
| 管理员密码明明改对了却登录失败 | 密码里含 `$ " ' #` 等字符会被 compose 变量替换吃掉。**只用字母和数字** |

---

## 十二、安全建议

1. **务必修改 `APP_SECRET`**。它是 JWT 签名密钥，默认值公开；泄露即可伪造管理员 token。
   （`deploy.sh` 首次运行会自动生成随机值。）
2. 修改 MySQL/PG 的默认密码，不要使用样例里的 `qltools_password`。
3. `/api/open/submit` 是免登录写接口，**不要直接暴露到公网**。建议放在 Nginx 反代后，
   加 IP 白名单、Basic Auth 或 WAF 限速。
4. `.env` 内含密钥，已被 `.gitignore` 忽略，**不要提交到版本库**；
   推送到镜像仓库的镜像里也不包含 `.env`（构建上下文已排除）。
5. 镜像默认以 root 运行。若需加固，可在 `Dockerfile` 运行阶段创建非 root 用户并
   `chown /app/data`；注意使用 bind mount 时要同步宿主机目录属主。
6. 定期备份数据库卷；SQLite 模式下直接备份 `/app/data/ql_tools_v2.db` 即可。
