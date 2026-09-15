# QLToolsV2 · Docker 部署

青龙面板的**环境变量提交 / 管理中间件**（Go + Gin + Ent ORM）。

它做一件事：把外部提交上来的环境变量值，按「变量 → 面板」的绑定关系，
**自动轮询分发并写入一台或多台青龙面板的 `/open/envs`**。

本仓库是**开箱即用的容器化版本**：镜像已构建并发布，部署只需拉镜像 + 起容器。

| | |
|---|---|
| 镜像 | `chungg/qltoolsv2:latest` |
| 平台 | `linux/amd64` |
| 端口 | `1500` |
| 健康检查 | `GET /ping` → `pong` |
| 运行期依赖 | **无**（数据库默认用内置 SQLite；不需要 Redis、不需要 Node、不需要 Nginx） |

---

## 30 秒部署

### 最简：一条 `docker run`

```bash
docker run -d --name qltools \
  -p 1500:1500 \
  -v qltools_data:/app/data \
  -e APP_SECRET="$(openssl rand -base64 48)" \
  --restart unless-stopped \
  chungg/qltoolsv2:latest
```

### 推荐：用 compose（便于后续改配置、切数据库）

```bash
cp .env.example .env      # 至少改掉 APP_SECRET
docker compose up -d
```

或者直接跑部署脚本，它会自动生成 `.env`（含随机 `APP_SECRET`）、拉镜像、
启动容器、等待健康检查通过，最后打印访问地址：

```bash
./scripts/deploy.sh --pull
```

### 验证

```bash
curl http://127.0.0.1:1500/ping     # 期望输出：pong
```

然后浏览器打开 `http://<服务器IP>:1500`。

### 两个入口，别搞混

| 地址 | 页面 | 是否需要登录 |
|------|------|--------------|
| `/` | **免密提交页**（重定向到 `/commitVariable`），给外部提交数据用 | 不需要 |
| `/admin` | **后台管理员登录页** | 需要账号密码 + 验证码 |
| `/ping` | 健康检查，返回 `pong` | 不需要 |

> `/admin` 与 `/login` 是同一个页面的两个地址，用哪个都能进后台。

---

## 跑起来之后

### 1) 拿到管理员账号（三选一）

1. **自动创建（最省事）**：在 `.env` 里填好
   ```ini
   QLTOOLS_ADMIN_USERNAME=admin
   QLTOOLS_ADMIN_PASSWORD=你的密码
   ```
   重启容器，首次启动发现数据库里没有用户就会自动建号，直接登录即可。
   `./scripts/deploy.sh` 首次生成 `.env` 时会自动填一个随机密码并在结尾打印出来。
2. **页面自助注册**：打开 `http://<IP>:1500/admin`，点表单下方的 **「注册账号」**，
   填用户名/密码/验证码即可。**系统只允许注册一个账号，首个注册者即为管理员。**
3. **忘记密码**：`.env` 里把 `QLTOOLS_ADMIN_RESET=1` 并填好
   `QLTOOLS_ADMIN_PASSWORD`，重启一次容器，密码会被重置成该值；**重置完记得改回 `0`**，
   否则每次重启都会把密码改回去。

> 登录页的输入框里只有「请输入用户名 / 请输入密码」这类占位提示，
> 系统**不会**预置 `admin/admin` 这种默认账号。没有账号时请用上面第 1 或第 2 种方式创建。

### 2) 在青龙面板侧准备 Open API 凭证

青龙面板 → **系统设置 → 应用设置 → 新建应用** → 得到 `client_id` 与 `client_secret`。

> 这组凭证是 QLTools 连接青龙用的身份，**不是**青龙的登录账号密码。

### 3) 在 QLTools 后台配置面板与变量

- **面板管理 → 新增面板**：填青龙地址（如 `http://1.2.3.4:5700`）+ `client_id` + `client_secret`，
  可点「测试连接」验证。
- **变量管理 → 新增变量**：填变量名（如 `JD_COOKIE`）、`quantity`、`mode`、`cdk_limit`
  —— 这四个都是**必填**；不启用卡密就填 `0`。
  **是否启用 KEY 校验由 `enable_key` 控制，不是 `cdk_limit`。**
- 在变量详情里**绑定到已启用的面板**，并确认变量本身是「启用」状态。

> 变量与面板只要有一方是禁用状态，提交就会返回 `submitted_to = 0`。

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

## 常用运维

```bash
docker compose logs -f qltools      # 看日志
docker compose restart qltools      # 重启
docker compose down                 # 停止（保留数据卷）
docker compose pull && docker compose up -d   # 升级到最新镜像
```

**回滚**：把 `.env` 里的 `IMAGE_TAG` 改成之前构建产出的提交号标签
（格式 `sha-<7位提交号>`）后重新 `docker compose up -d`。

**切换数据库**（SQLite → MySQL / PostgreSQL）：

```bash
./scripts/deploy.sh mysql       # 应用 + MySQL 8
./scripts/deploy.sh postgres    # 应用 + PostgreSQL 16
```

数据表由程序在首次启动时**自动迁移创建**，不需要手工执行 SQL。
从 SQLite 换到外部数据库属于**换库**，原数据不会自动迁移。

> ⚠️ `docker compose down -v` 会连数据卷一起删除，**数据全部丢失**，慎用。

---

## 目录结构

```
QLToolsV2-docker/
├── Dockerfile                      # 多阶段构建：src/ 编译 -> debian-slim 运行
├── entrypoint.sh                   # 生成 config.yaml；等待数据库就绪后启动
├── docker-compose.yml              # SQLite（零外部依赖）
├── docker-compose.mysql.yml        # 应用 + MySQL 8
├── docker-compose.postgres.yml     # 应用 + PostgreSQL 16
├── docker-compose.build.yml        # 本地构建用的 override（拉镜像部署不需要）
├── .env.example                    # 环境变量样例
├── scripts/
│   ├── deploy.sh                   # 一键部署
│   ├── build-push.sh               # 构建镜像并推送到镜像仓库
│   ├── github-bootstrap.sh         # 建仓库 → 推送 → 配 Secret → 触发云端构建
│   └── gh-set-secret.py            # 上面脚本的辅助程序
├── src/                            # 服务端源码（含已内嵌的前端产物 web/dist）
├── configs/config.yaml             # 配置参考样例（容器不读它）
├── examples/                       # 提交数据的两条示例
├── NOTICE.md                       # 第三方代码许可
├── DEPLOY.md                       # 完整部署手册
└── README.md
```

容器内布局：

```
/app
├── QLToolsV2            # 二进制（前端已通过 go:embed 打包进去）
├── entrypoint.sh
├── configs/config.yaml  # 每次启动由 entrypoint.sh 生成
└── data/                # 卷挂载点 -> 命名卷 qltools_data
    └── ql_tools_v2.db   # SQLite 模式下的数据库文件
```

---

## 环境变量速查

最常改的几个（完整表格见 [DEPLOY.md](DEPLOY.md) 第六节）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HOST_PORT` | `1500` | 宿主机映射端口，被占用时改掉 |
| `APP_SECRET` | `QLToolsV2` | **JWT 签名密钥，生产必须改**（`deploy.sh` 会自动生成随机值） |
| `DB_TYPE` | `sqlite` | `sqlite` / `mysql` / `postgres` |
| `TZ` | `Asia/Shanghai` | 时区 |
| `APP_MODE` | `release` | 改成 `debug` 才会开放 `/swagger/index.html` |
| `QLTOOLS_ADMIN_USERNAME` | `admin` | 初始管理员用户名 |
| `QLTOOLS_ADMIN_PASSWORD` | 空 | 初始管理员密码。**留空则不自动建号**，改用 `/admin` 页面的「注册账号」 |
| `QLTOOLS_ADMIN_RESET` | `0` | 置 `1` 重启一次即把已存在账号的密码重置成上面的值（找回密码用，用完改回 `0`） |
| `IMAGE_REPO` | `chungg/qltoolsv2` | 想用自己构建的镜像时改这里 |
| `IMAGE_TAG` | `latest` | 也可填 `sha-<提交号>` 精确锁定并支持回滚 |

---

## 需要知道的几件事

- **响应体统一为** `{"code": 20000, "msg": "Success", "data": {...}}`，成功码是 **20000**，不是 200 或 0。
- **`APP_ADDRESS` 不起作用**：HTTP 服务只使用 `port`，进程在容器内始终监听 `0.0.0.0`，
  端口映射不受它影响。
- **不需要 Redis**：缓存是进程内 `gcache`，`config.yaml` 里的 `cache` 段不生效。
- **不需要 Node.js**：前端产物已随源码提供，并通过 `go:embed` 打进二进制。
- **PostgreSQL 的 `DB_CONFIG` 必须用 libpq 风格**（如 `sslmode=disable`），
  不能沿用 MySQL 的 `charset=utf8mb4&...`，否则连接直接失败。
- **脚本必须是 LF 换行**，CRLF 会让容器启动即报
  `/usr/bin/env: 'bash\r': No such file or directory`。
- `/api/open/submit` 是**免登录写接口**，不要直接暴露到公网，建议加反代 + IP 白名单 + 限速。

---

## 从源码自行构建（可选）

只有当你要改代码、或想构建 ARM 等其他架构的镜像时才需要。

```bash
# 本机有 Docker
./scripts/deploy.sh --build                       # 本地构建并启动
./scripts/build-push.sh --push                    # 构建并推送到自己的镜像仓库
./scripts/build-push.sh --platforms linux/amd64,linux/arm64 --push   # 多架构

# 本机没有 Docker —— 用 GitHub Actions 云端构建
export GH_TOKEN=ghp_xxxx              # GitHub 令牌，需 repo + workflow 权限
export DOCKERHUB_USERNAME=你的用户名
export DOCKERHUB_TOKEN=dckr_pat_xxxx  # Docker Hub Access Token
./scripts/github-bootstrap.sh         # 建仓库 → 推送 → 配 Secret → 触发构建
```

源码在 `src/`（306 个文件，含已入库的前端产物 `web/dist`），构建期只下载 Go 模块，
不访问任何代码托管站点。若需**完全离线构建**，见 [DEPLOY.md](DEPLOY.md) 的「完全离线 / 内网部署」。

---

© 部分源码为第三方开源项目，采用 Apache License 2.0，详见 [NOTICE.md](NOTICE.md)。
