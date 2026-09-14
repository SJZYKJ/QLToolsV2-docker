# QLToolsV2 Docker 部署手册

> 本文是这套**自包含、不依赖上游仓库**的 Docker 部署方案的完整交付说明：
> 部署路线、文件清单、依赖清单、环境变量、逐步操作、排错，以及「与上游源码逐行核对」的结论。
> 只想快点跑起来 → 看 [README.md](README.md) 的快速开始。

---

## 一、这是什么

上游项目 [nuanxinqing123/QLToolsV2](https://github.com/nuanxinqing123/QLToolsV2) 是
**青龙面板的环境变量第三方提交 / 管理中间件**（Go + Gin + Ent ORM，已停止维护）。

它做一件事：把外部提交上来的环境变量值，按「变量 → 面板」的绑定关系，
自动轮询分发并写入一台或多台青龙面板的 `/open/envs`。

**为什么要单独做一套部署文件：**

1. 上游仓库**根目录没有 Dockerfile** —— 它的 CI 里写了 `file: ./Dockerfile`，
   但该文件实际并不存在，官方镜像构建跑不通。
2. 上游已废弃，**随时可能被归档或删除** —— 如果构建时去 `git clone`，将来必然失败。

因此本方案做了两件事：补齐构建与编排文件，并把**上游源码内嵌到 `upstream/`**，
让构建过程与上游仓库是否存活彻底解耦。

---

## 二、三种部署路线

先明确概念：**「构建」**是把源码编译成镜像，**「部署」**是把镜像跑起来。
构建完可以推到自己的镜像仓库，之后部署端就再也不需要源码、也不需要联网编译。

### 路线 A · 本地一键部署（最省事，适合先跑通）

源码已在 `upstream/`，本机直接编译并启动：

```bash
./scripts/deploy.sh            # 或 ./scripts/deploy.sh mysql / postgres
```

首次运行会自动生成 `.env` 与随机 `APP_SECRET`，然后构建镜像、启动容器、
等待健康检查通过，最后打印访问地址。**除 Go 模块代理外不访问任何上游。**

### 路线 B · 构建一次，推送到自己的 Docker Hub（推荐用于生产）

```bash
docker login                          # 登录你的 Docker Hub 账号
# 在 .env 里填 IMAGE_REPO=你的用户名/qltoolsv2
./scripts/build-push.sh --push        # 构建并推送
```

之后**部署端只需要 `.env` + compose 文件**，无需源码：

```bash
# 目标服务器上
cp .env.example .env
# 填入 IMAGE_REPO=你的用户名/qltoolsv2
./scripts/deploy.sh            # 自动拉取镜像并启动
```

多架构（同时支持 amd64 / arm64）：

```bash
./scripts/build-push.sh --platforms linux/amd64,linux/arm64 --push
```

### 路线 C · 完全离线 / 内网部署

三种递进的做法，按你的隔离程度选择：

**C1. 导出镜像文件搬运（最简单）**

```bash
# 有网机器
./scripts/build-push.sh
docker save qltoolsv2:latest -o qltoolsv2.tar
# 拷贝 tar 到内网机器
docker load -i qltoolsv2.tar
./scripts/deploy.sh
```

**C2. 内网自建镜像仓库**

把 `IMAGE_REPO` 指向内网 registry（如 `registry.intra:5000/qltoolsv2`），
`build-push.sh --push` 与 `deploy.sh` 都能直接工作。

**C3. 连带 Go 依赖一起离线（真正零外网构建）**

默认构建仍需要访问 Go 模块代理。若连代理也不能访问，先固化依赖：

```bash
# 用容器生成 vendor/，本机无需安装 Go
docker run --rm -v "$PWD/upstream:/src" -w /src golang:1.24-bookworm \
  sh -c 'go mod download && go mod vendor'
```

> Windows 下若路径转换报错，改用绝对路径并加 `MSYS_NO_PATHCONV=1`，例如：
> `MSYS_NO_PATHCONV=1 docker run --rm -v "D:/path/to/upstream:/src" ...`

`Dockerfile` 检测到 `upstream/vendor/` 会自动切到 `-mod=vendor` 离线模式，
此后构建不再访问任何网络。

---

## 三、文件清单

| 文件 / 目录 | 作用 | 是否必需 |
|------|------|----------|
| `upstream/` | **内嵌的上游源码**（锁定提交，含前端产物 `web/dist` 与 `LICENSE`）。构建的唯一源码来源 | **必需** |
| `Dockerfile` | 多阶段构建：从 `upstream/` 编译，运行期用 debian-slim | **必需** |
| `entrypoint.sh` | 按环境变量生成 `config.yaml`、等待数据库就绪、以 `-config` 启动程序 | **必需** |
| `scripts/deploy.sh` | **一键部署**：检查环境 → 生成 .env → 拉镜像或本地构建 → 启动 → 等待健康 | **必需** |
| `scripts/build-push.sh` | 构建镜像并（可选）推送到自己的 Docker Hub | 推荐 |
| `scripts/fetch-upstream.sh` | 更新/重新获取上游源码。**唯一需要访问上游的入口** | 可选 |
| `docker-compose.yml` | 默认方案：单容器 + SQLite，零外部依赖 | 三选一 |
| `docker-compose.mysql.yml` | 生产方案 A：应用 + MySQL 8 | 三选一 |
| `docker-compose.postgres.yml` | 生产方案 B：应用 + PostgreSQL 16 | 三选一 |
| `docker-compose.build.yml` | 构建覆盖文件（override），为上面三个补上 `build:` 段 | 本地构建时必需 |
| `.env.example` | 环境变量样例；`deploy.sh` 会据此自动生成 `.env` | 推荐 |
| `.dockerignore` | 精简构建上下文（**注意：不能排除 `upstream/`**） | 推荐 |
| `.gitattributes` | 强制 shell/yaml 用 LF 换行，防止 Windows 检出成 CRLF 破坏容器启动 | 推荐 |
| `.gitignore` | 忽略 `.env` 等敏感与临时文件 | 推荐 |
| `UPSTREAM.md` | 上游来源、锁定提交、许可证与合规说明 | 推荐 |
| `configs/config.yaml` | 配置参考样例（**容器不读它**；配合 `KEEP_CONFIG=1` 可挂载使用） | 参考 |
| `examples/submit.sh` | 用 curl 提交一条数据（公开接口，免登录） | 可选 |
| `examples/submit_to_qinglong.py` | 一键：登录 → 建面板 → 建变量 → 绑定 → 提交 | 可选 |
| `README.md` / `DEPLOY.md` | 快速上手 / 本文 | 推荐 |

---

## 四、目录结构

### 4.1 宿主机（本仓库）

```
QLToolsV2-docker/
├── upstream/                        # ★ 内嵌上游源码（306 文件，锁定提交）
│   ├── .upstream-rev                #   版本记录：仓库 / 提交 / 获取时间
│   ├── LICENSE                      #   Apache-2.0
│   ├── go.mod / go.sum
│   ├── cmd/  internal/  configs/
│   └── web/dist/                    #   前端产物（158 文件，已被 go:embed）
├── scripts/
│   ├── deploy.sh                    # 一键部署
│   ├── build-push.sh                # 构建 + 推送
│   └── fetch-upstream.sh            # 更新上游源码（可选）
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
├── UPSTREAM.md                      # 上游来源与许可证说明
├── DEPLOY.md  README.md
└── .workbuddy/                      # 工作记录（与部署无关）
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

前端资源**不需要目录**：上游 `web/embed.go` 用 `//go:embed all:dist` 把
Vue 构建产物打进了二进制，运行期既不需要 Node.js，也不需要拷贝 `web/dist`。

---

## 五、依赖清单

### 5.1 宿主机构建依赖

| 项 | 要求 | 说明 |
|----|------|------|
| Docker Engine | 20.10+（推荐 24+） | 需要 BuildKit |
| Docker Compose | v2（`docker compose` 子命令） | 不是老的 `docker-compose` v1 |
| 网络 | **只需能访问 Go 模块代理** | GitHub 仅在执行 `fetch-upstream.sh` 时才需要 |
| 磁盘 | 约 2–3 GB | 构建缓存 + 镜像 |
| 工具 | `curl` / `tar`（仅 `fetch-upstream.sh` 需要） | 日常部署不需要 |

### 5.2 基础镜像

| 阶段 | 镜像 | 用途 |
|------|------|------|
| 构建 | `golang:1.24-bookworm` | 编译；自带 gcc，满足 CGO |
| 运行 | `debian:bookworm-slim` | 约 100 MB 级 |
| 数据库 | `mysql:8.0` / `postgres:16-alpine` | 按需 |

### 5.3 构建期系统包

`git`、`ca-certificates`、`tzdata`

（`git` 只为兼容少数走 VCS 的模块而保留；源码本身来自构建上下文，不再 clone。）

### 5.4 运行期系统包

`ca-certificates`（访问青龙 HTTPS）、`tzdata`（时区）、`wget`（健康检查）、`bash`（entrypoint）

### 5.5 Go 模块（上游 `go.mod`，24 个直接依赖）

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

> **`APP_ADDRESS` 为什么不生效：** 上游 `internal/app/bootstrap.go` 启动 HTTP 服务时写的是
> `Addr: fmt.Sprintf(":%d", config.Config.App.Port)` —— 只取了 `port`，没有用 `address`。
> 因此进程在容器内始终监听 `0.0.0.0`，端口映射不受该变量影响。

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

### 6.3 镜像与构建（部署端最关键）

| 环境变量 | 默认值 | 作用 |
|----------|--------|------|
| `IMAGE_REPO` | 空 | 镜像仓库，如 `yourname/qltoolsv2`。**填了就用镜像，留空就用本地源码构建** |
| `IMAGE_TAG` | `latest` | 镜像标签 |
| `PLATFORMS` | 空 | 多架构构建，如 `linux/amd64,linux/arm64` |
| `GOPROXY` | `https://goproxy.cn,https://proxy.golang.org,direct` | Go 模块代理（构建期生效） |

### 6.4 容器行为控制（不写入配置文件）

| 环境变量 | 默认值 | 作用 |
|----------|--------|------|
| `CONFIG_PATH` | `/app/configs/config.yaml` | 生成/读取配置文件的位置 |
| `KEEP_CONFIG` | `0` | 设为 `1` 且文件已存在时跳过生成，直接使用挂载进来的配置 |
| `HOST_PORT` | `1500` | 宿主机映射端口（仅 compose 使用） |

### 6.5 Dockerfile 构建参数（`--build-arg`）

| 参数 | 默认值 | 作用 |
|------|--------|------|
| `GOPROXY` | `https://goproxy.cn,https://proxy.golang.org,direct` | Go 模块代理，国内加速 |
| `TZ` | `Asia/Shanghai` | 构建镜像的时区 |

> 注意：源码已内嵌，**不再有 `QLTOOLS_REPO` / `QLTOOLS_REF` 这类构建参数**。
> 要切换上游版本，请改用 `./scripts/fetch-upstream.sh --sha <commit>`。

---

## 七、部署步骤

### 步骤 0 · 前置检查

```bash
docker version          # 需要 20.10+
docker compose version  # 需要 v2
```

### 步骤 1 · 一键部署（SQLite，建议先跑通）

```bash
./scripts/deploy.sh
```

脚本会依次完成：检查 Docker → 生成 `.env`（含随机 `APP_SECRET`）→
构建镜像 → 启动容器 → 等待健康检查 → 打印访问地址。

日志出现 `数据库连接成功 (Ent)` 与 `监听端口: 1500` 即为正常：

```bash
curl http://127.0.0.1:1500/ping     # 期望输出 pong
```

<details>
<summary>不使用脚本时的等价手工命令</summary>

```bash
cp .env.example .env
# 改掉 APP_SECRET：openssl rand -base64 48
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```
</details>

### 步骤 2 · 注册管理员（**只在第一次做**）

浏览器打开 `http://<服务器IP>:1500`。

> **系统只允许注册一个账号，首个注册者即为管理员。**
> 注册需要填图形验证码（算术题），点验证码图片刷新。登录同样需要验证码。

登录后浏览器会拿到 `access_token`（JWT），后续管理类接口都要带它。

### 步骤 3 · 在青龙面板侧准备 Open API 凭证

青龙面板 → **系统设置 → 应用设置 → 新建应用**，得到 `client_id` 与 `client_secret`。
（这组凭证是 QLTools 连接青龙用的身份，不是青龙的登录账号密码。）

### 步骤 4 · 在 QLTools 后台配置面板与变量

1. **面板管理 → 新增面板**：填青龙地址（如 `http://1.2.3.4:5700`）+ `client_id` + `client_secret`，
   保存时会自动取 token，可点「测试连接」验证。
2. **变量管理 → 新增变量**：填变量名（如 `JD_COOKIE`）、`quantity`（负载数量）、`mode`、
   `cdk_limit`（必填，不启用卡密填 `0`）；**是否启用 KEY 校验由 `enable_key` 控制，不是 `cdk_limit`**。
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

数据表由 Ent 在**首次启动时自动迁移创建**，不需要手工执行任何 SQL。
entrypoint 会先等待数据库端口就绪再启动应用。

> 从 SQLite 切到 MySQL/PG 属于**换库**，原 SQLite 里的用户、面板、变量配置不会自动迁移，
> 需要在后台重新配置（或自行导出导入）。

### 步骤 7 · 发布到自己的 Docker Hub（可选）

```bash
docker login
# 编辑 .env：IMAGE_REPO=你的用户名/qltoolsv2
./scripts/build-push.sh --push
```

推送后，**任何机器**只要拿到本目录的 compose 文件与 `.env` 即可一键部署：

```bash
./scripts/deploy.sh             # 自动拉取镜像启动，无需源码、无需编译
```

### 步骤 8 · 更新上游版本（可选）

```bash
./scripts/fetch-upstream.sh --sha <新的提交>     # 或 --ref <分支/tag>
./scripts/build-push.sh --push
```

---

## 八、数据持久化与升级

| 部署方式 | 卷 | 内容 |
|----------|----|------|
| SQLite | `qltools_data` → `/app/data` | `ql_tools_v2.db` 数据库文件 |
| MySQL | `qltools_data` + `qltools_mysql_data` | 前者空置，后者是 MySQL 数据目录 |
| PostgreSQL | `qltools_data` + `qltools_postgres_data` | 同上 |

**只要不删卷，数据就不会丢。**

升级方式取决于你的镜像来源：

```bash
# 用自有镜像（路线 B）
./scripts/build-push.sh --push      # 构建机
./scripts/deploy.sh                 # 部署机，会自动拉取新镜像

# 用本地源码（路线 A）
./scripts/deploy.sh --build
```

回滚：把 `IMAGE_TAG` 改成之前推送的版本标签（`build-push.sh` 每次推送都会额外打一个
`YYYYMMDD` 日期标签）后重新 `./scripts/deploy.sh`。

> `docker compose down -v` 会删除所有卷（数据全丢），只在确认不需要数据时使用。

---

## 九、端口与接口速查

| 项 | 值 |
|----|----|
| 服务端口 | `1500` |
| 健康检查 | `GET /ping` → `pong` |
| 后台 UI | `GET /`（未匹配路由回落到内嵌的 index.html） |
| 指标 | `GET /metrics`（Prometheus） |
| Swagger | `GET /swagger/index.html`（**仅 `APP_MODE=debug`**） |
| 统一响应体 | `{"code": 20000, "msg": "Success", "data": {...}}` |
| 成功码 | **20000**（`CodeSuccess`），不是 200 / 0 |

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

## 十、排错

| 现象 | 原因与处理 |
|------|------------|
| `!! 缺少内嵌源码 upstream/go.mod` | `upstream/` 不完整。执行 `./scripts/fetch-upstream.sh` 重新获取 |
| `!! 拉取失败（镜像不存在、未 docker login…）` | `IMAGE_REPO` 写错或未登录。确认仓库名，或改回本地构建（`deploy.sh --build`） |
| 容器起不来，日志报 `fatal error config file` | `config.yaml` 没生成出来。上游用 viper 读不到配置会直接 panic。检查 `CONFIG_PATH` 指向的目录可写，或 `KEEP_CONFIG=1` 时挂载的文件是否真的存在 |
| 日志报 `failed creating schema resources` | 数据库连不上或权限不足。核对 `DB_HOST/PORT/NAME/USERNAME/PASSWORD`，以及 MySQL 账号是否有建表权限 |
| 用 PostgreSQL 时连接直接失败 | `DB_CONFIG` 沿用了 MySQL 的 charset 串。postgres 需要 libpq 风格，用 `sslmode=disable` |
| `/usr/bin/env: 'bash\r': No such file or directory` | 脚本是 CRLF 换行（Windows 编辑导致）。执行 `sed -i 's/\r$//' entrypoint.sh scripts/*.sh`，并保留仓库内的 `.gitattributes` |
| 提交返回 `submitted_to: 0` | 变量未启用，或绑定的面板处于禁用状态，或青龙 `client_id/secret` 不正确 / 青龙 Open API 没开 |
| 提交返回 `code: 49997`（请求过于频繁） | `/api/open/submit` 有令牌桶限速（2 req/s，容量 5），降低提交频率 |
| 注册提示「系统已存在用户」 | 全系统只允许一个账号。直接登录即可；忘记密码需清库中 `users` 表 |
| 验证码一直提示错误 | 验证码用**内存存储**，重启容器会失效，刷新页面重新取即可 |
| 端口 1500 被占用 | 在 `.env` 里改 `HOST_PORT=15001` |
| 构建很慢 | 首次要 `go mod download`。确认 `GOPROXY` 用的是 `https://goproxy.cn`；若已做 vendor 可完全离线 |
| 构建报 `requires go >= 1.24.x` | 镜像内 Go 版本偏低。Dockerfile 已设 `GOTOOLCHAIN=auto` 兜底自动拉取匹配工具链 |
| `deploy.sh` 说 Docker 守护进程未运行 | 启动 Docker Desktop / `systemctl start docker` |

---

## 十一、与上游源码的一致性核对

以下结论逐行核对了上游 `master` 分支源码（306 个文件全量）后得出，
用来解释本方案为什么这么写——其中若干条与直觉不符，属于容易踩的坑。

| # | 结论 | 源码依据 |
|---|------|----------|
| 1 | 上游**根目录没有 Dockerfile**，CI 里的 `file: ./Dockerfile` 是失效引用 | 全量文件树核对；`.github/workflows/build_docker_image.yml` |
| 2 | 启动参数支持 `-config` 与 `-c`，默认路径是相对的 `configs/config.yaml` | `internal/app/bootstrap.go`、`internal/app/initializer/viper.go` |
| 3 | 配置文件读不到会 **panic**，所以 entrypoint 必须生成它 | `viper.go` 中 `panic(fmt.Errorf("fatal error config file: %w", err))` |
| 4 | **`app.address` 不生效**，HTTP 服务只用 port，始终监听全部网卡 | `bootstrap.go`: `Addr: fmt.Sprintf(":%d", ...)` |
| 5 | 前端已 `//go:embed all:dist` 内嵌，**不需要 Node 构建** | `web/embed.go`、`internal/app/initializer/web.go` |
| 6 | 缓存是进程内 `gcache`，**不需要 Redis**，`cache` 配置段实际不生效 | `internal/app/initializer/cache.go` |
| 7 | SQLite 只用 `db.name` 作文件路径，并自行追加 `?_fk=1` | `internal/data/client.go`: `sql.Open("sqlite3", cfg.Name+"?_fk=1")` |
| 8 | PostgreSQL 的 `db.config` 会**原样拼进 DSN**，必须是 libpq 风格参数 | `client.go`: `host=%s port=%d user=%s password=%s dbname=%s %s` |
| 9 | 成功响应码是 **20000**，字段名是 `msg` 不是 `message` | `internal/pkg/response/code.go`、`response.go` |
| 10 | 健康检查 `/ping` 返回 `pong` | `internal/app/initializer/router.go` |
| 11 | **注册和登录都必须过验证码**，验证码存内存 | `internal/controller/auth.go`、`base64Captcha.DefaultMemStore` |
| 12 | 系统**只允许注册一个用户**，首个即为管理员 | `internal/service` 注册逻辑 |
| 13 | 表结构由 Ent 启动时**自动迁移**，无需手工建表 | `client.go`: `Client.Schema.Create(...)` |
| 14 | `/api/open/submit` 免登录但限速更严（2 req/s，桶容量 5） | `internal/controller/open.go`、`internal/middleware/rate_limit.go` |
| 15 | 鉴权头是 `Authorization: Bearer <token>`，且只接受 access 类型 token | `internal/middleware/jwt.go` |
| 16 | 变量创建时 `quantity`、`mode`、`cdk_limit` 都是**必填**；新变量默认可能禁用 | `internal/schema/env.go` |
| 17 | 控制 KEY（卡密）校验的是 `enable_key` 字段，不是 `cdk_limit=0` | `internal/schema/env.go` |
| 18 | 上游 `Makefile` 的 `gen` 目标引用了已不存在的 `cmd/generate/generate.go` | `Makefile` vs 实际文件树；入口只有 `cmd/main.go` |
| 19 | `web/dist` 前端产物**已随源码入库**（158 文件），因此可纯 Go 构建 | 上游仓库文件树 |
| 20 | 上游许可证是 **Apache-2.0**，允许再分发（需保留 LICENSE） | `upstream/LICENSE` |

---

## 十二、安全建议

1. **务必修改 `APP_SECRET`**。它是 JWT 签名密钥，默认值公开；泄露即可伪造管理员 token。
   （`deploy.sh` 首次运行会自动生成随机值。）
2. 修改 MySQL/PG 的默认密码，不要使用样例里的 `qltools_password`。
3. `/api/open/submit` 是免登录写接口，**不要直接暴露到公网**。建议放在 Nginx 反代后，
   加 IP 白名单、Basic Auth 或 WAF 限速。
4. `.env` 内含密钥，已被 `.gitignore` 忽略，**不要提交到版本库**；
   推送到 Docker Hub 的镜像里也不包含 `.env`（构建上下文已排除）。
5. 镜像默认以 root 运行。若需加固，可在 `Dockerfile` 运行阶段创建非 root 用户并
   `chown /app/data`；注意使用 bind mount 时要同步宿主机目录属主。
6. 定期备份数据库卷；SQLite 模式下直接备份 `/app/data/ql_tools_v2.db` 即可。
