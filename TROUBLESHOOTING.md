# QLToolsV2 排错手册

> 部署过程中实际踩过的坑，按「现象」组织，每条都给**原因**和**解决办法**。
> 部署步骤本身见 [README.md](README.md) / [DEPLOY.md](DEPLOY.md)。

---

## 目录

- [〇、先跑这三条命令](#〇先跑这三条命令)
- [一、容器起不来](#一容器起不来)
- [二、容器起来了，但页面不对](#二容器起来了但页面不对)
- [三、部署期间报错](#三部署期间报错)
- [四、接口调用异常](#四接口调用异常)
- [五、提交后存进去的值不对（正则配置）](#五提交后存进去的值不对正则配置)
- [六、命令速查](#六命令速查)

---

## 〇、先跑这三条命令

90% 的问题在这三条输出里就能看出来：

```bash
docker compose ps                          # 容器状态：是否 healthy
docker compose logs --tail 60 qltools      # 启动日志：报错都在这
curl -s localhost:1500/ping; echo          # 期望 pong
```

确认容器内的环境变量是否真的传进去了（`.env` 改了但没生效时最常查这个）：

```bash
docker exec qltools_v2 env | grep -E 'APP_|QLTOOLS_|DB_'
```

> ⚠️ **别把「服务名」和「容器名」搞混**：
> -  系列命令用**服务名** （如 ）
> -  /  用**容器名** （由  的  决定）
>
> 如果你曾经用  手工部署过，那是**另一个容器**，
>  操作的是它，而不是 compose 起的 。

---

## 一、容器起不来

### 1.1 `exec /usr/bin/env: 'bash\r': No such file or directory`

**原因**：`entrypoint.sh` 被 Windows 检出成 CRLF 换行，Linux 里把 `\r` 当成解释器名字的一部分。

**解决**：仓库已用 `.gitattributes` 强制 `*.sh` 走 LF。若本地文件已被污染：

```bash
sed -i 's/\r$//' entrypoint.sh scripts/*.sh && docker compose up -d --force-recreate
```

### 1.2 日志停在「等待数据库就绪」然后退出

**原因**：`DB_TYPE` 与实际数据库不匹配，或数据库密码/地址不对。

**解决**：核对 `.env` 里的 `DB_TYPE`（`sqlite` / `mysql` / `postgres`）与所选 compose 文件一致。
SQLite 模式不会有这个问题，它不依赖外部服务。

### 1.3 端口被占用

```
Error response from daemon: driver failed programming external connectivity ... bind: address already in use
```

**解决**：改 `.env` 里的 `HOST_PORT=1501`，然后 `docker compose up -d`。
查占用者：`ss -lntp | grep 1500`

---

## 二、容器起来了，但页面不对

### 2.1 点「退出登录」弹出 `Error` ✅ 已修复

**现象**：登录正常，点退出登录只弹一个 `Error`，没有别的信息，且退不出去。

**原因**：前后端 HTTP 方法不一致。

- 前端产物里写的是 `Ht.post("/api/auth/logout")`，**POST**；
- 后端 `AuthRequiredRouter` 里早期只注册了 `router.GET("/logout", ...)`，**只有 GET**；
- POST 匹配不到路由，落到 `SetupWebFrontend` 的 `NoRoute`。而 `NoRoute` 对不带 `.` 的路径
  会返回前端 `index.html`（**HTTP 200 + HTML**）；
- 前端响应拦截器判断 `res.data.code !== 20000`，但 HTML 里根本没有 `code` 字段，
  于是走 `n.msg || "Error"` 分支，弹出 `Error`。

**修复**（已提交）：`internal/controller/auth.go` 注册 `POST /logout`（保留 GET 兼容旧脚本）。
同时加固 `internal/app/initializer/web.go`：`/api/*` 路径未匹配时直接返回
`{"code": 50001, "msg": "接口不存在: POST /api/xxx"}` 的 JSON，而不是 HTML。

> **通用教训**：`NoRoute` 用 index.html 兜底是 SPA 的标准做法，但它会把
> 「接口不存在 / 方法写错」伪装成「后端异常」。凡是从前端看到**光秃秃一个 `Error`**，
> 优先怀疑请求压根没匹配到路由，而不是后端逻辑出错。
>
> 自查：浏览器 F12 → Network → 找到那条红色请求，看 **HTTP 状态码和响应体**。
> 如果是 `200` 且响应体是 HTML，就是这个原因。

### 2.2 登录报「账号不存在或查询失败」

**原因**：系统**不预置任何默认账号**。`service/auth.go` 只在 `users` 表为空时允许注册一个用户，
登录页输入框里的文字只是占位提示，从来不是 `admin/admin`。

**解决**（三选一）：

1. 在 `.env` 里设好下面两项后重启容器，首次启动会自动建号：
   ```ini
   QLTOOLS_ADMIN_USERNAME=admin
   QLTOOLS_ADMIN_PASSWORD=只有字母和数字的密码
   ```
2. 打开 `http://<IP>:1500/admin`，点表单下方的「注册账号」自助注册（全系统只允许一个账号）。
3. 已经建过号但忘了密码 → 设 `QLTOOLS_ADMIN_RESET=1` 重启一次重置密码，**用完改回 `0`**，
   否则每次重启都会把密码改回去。

### 2.3 打开 `/admin` 不是登录页

**原因**：早期前端路由表里没有 `/admin`，访问它会落到 404 通配路由。

**修复**（已修复）：前端路由给 `/login` 加了 `alias: "/admin"`，两者现在是同一个页面。

如果仍不正常，确认浏览器没有缓存旧的前端产物：强刷（`Ctrl/Cmd + Shift + R`）。

### 2.4 页脚版权链接指向别的仓库

**原因**：链接硬编码在打包产物 `src/web/dist/assets/index-*.js` 里。

**修复**（已修复）：已改为本仓库地址。若你要换成自己的，直接改这个文件里的
`href:"https://github.com/..."` 即可（改完顺手把同名 `.gz` 重新压一下，虽然运行时不读它）。

### 2.5 打开任何地址都是同一个页面 / 刷新后 404

这是 **Vue Router history 模式**的正常表现：`NoRoute` 会把所有非 `/api/`、
不带 `.` 的路径都交给 `index.html`，由前端路由接管。
只要 `/ping` 能返回 `pong`，就说明服务是好的。

---

## 三、部署期间报错

### 3.1 `docker compose up -d` 报 `yaml: line 2: mapping values are not allowed in this context`

**原因**：`docker-compose.yml` 的第 1 行不是 `services:`。
最常见是**从 Markdown 代码块复制时，把 ` ```bash ` 围栏也一起粘进去了**，
于是第 1 行成了普通文本，第 2 行才开始出现 `键: 值`。

**先确认**：

```bash
head -5 docker-compose.yml
```

**解决**：用 base64 重写，彻底避开转义与粘贴问题：

```bash
cd /root/QLToolsV2-docker
mv docker-compose.yml docker-compose.yml.bad

echo '<base64 字符串>' | base64 -d > docker-compose.yml

docker compose config >/dev/null && echo "✅ YAML OK"
```

> `docker compose config` 只解析不启动，是修改编排文件后最安全的校验手段。

**同类问题**：`.env` 混进围栏符号会让变量静默失效。自查：

```bash
grep -nE '^```|^cat |^EOF' .env
```

有输出就重写（`printf` 逐行写，没有 heredoc、没有引号嵌套）：

```bash
SECRET=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48)
printf 'TZ=Asia/Shanghai\nAPP_MODE=release\nAPP_PORT=1500\nHOST_PORT=1500\nAPP_SECRET=%s\nAPP_ADDRESS=0.0.0.0\nQLTOOLS_ADMIN_USERNAME=admin\nQLTOOLS_ADMIN_PASSWORD=你的密码\nQLTOOLS_ADMIN_RESET=0\nIMAGE_REPO=chungg/qltoolsv2\nIMAGE_TAG=latest\n' "$SECRET" > .env
chmod 600 .env
```

### 3.2 `.env` 改了，但容器里没生效

**原因 A**：`.env` 是 compose 的**变量替换源**，不是容器的环境变量。
变量必须在 `docker-compose.yml` 的 `environment:` 段里被显式映射，容器才拿得到。

**原因 B**：只改了 `.env` 没重建容器。

**解决**：

```bash
docker exec qltools_v2 env | grep QLTOOLS   # 先确认到底有没有传进去
docker compose up -d                        # 有变化时 compose 会自动重建容器
```

### 3.3 密码里带特殊字符，登录一直失败

**原因**：`$ " ' #` 等字符会被 compose 的变量替换吃掉，实际生效的密码和你写的不一样。

**解决**：`QLTOOLS_ADMIN_PASSWORD` **只用字母和数字**。

### 3.4 服务器上 `git clone` 失败：`Failure when receiving data from the peer`

**原因**：服务器到 GitHub 的网络不通（国内云主机很常见）。

**关键认知**：**更新镜像根本不需要 GitHub**，Docker Hub 通了就够了：

```bash
cd /root/QLToolsV2-docker && docker compose pull && docker compose up -d
```

**仓库源码怎么弄到服务器上**（按可行性排序）：

1. **本地 scp 上去**（最稳，本地已经有仓库时首选）：
   ```bash
   scp docker-compose.yml .env.example root@<IP>:/root/QLToolsV2-docker/
   ```
2. **走镜像加速地址**：
   ```bash
   git clone --depth 1 https://ghfast.top/https://github.com/SJZYKJ/QLToolsV2-docker.git
   ```
3. **手工落文件**：只需 `docker-compose.yml` + `.env` 两个文件就能跑起来，
   内容可直接照抄 [DEPLOY.md](DEPLOY.md)，或用上面 3.1 的 base64 方式写入。

### 3.5 已经用 `docker run` 手工跑起来了，想改成 compose 管理

**原因**：手工 `docker run` 起的容器没有 `com.docker.compose.*` 标签，
`docker inspect` 查不到 compose 工作目录，目录里自然也没有编排文件。

**判断依据**：

```bash
docker inspect <容器名> --format '{{range .Config.Env}}{{println .}}{{end}}'   # 抄出原有环境变量
docker inspect <容器名> --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
docker inspect <容器名> --format 'project_dir={{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

`project_dir=` 为空就是手工容器。

**接管步骤**：

```bash
cd /root/QLToolsV2-docker
# 1. 按 3.1 的方式写好 docker-compose.yml
# 2. 按 3.1 的方式写好 .env（APP_SECRET 沿用上面抄出来的原值，
#    这样已登录的会话不会立刻失效；也可以重新生成，代价是所有人都要重新登录）
# 3. 删掉手工容器（它占着端口，不删会冲突）
docker rm -f <旧容器名>
# 4. 用 compose 起来
docker compose up -d
```

> **数据不会丢**：SQLite 库文件在数据卷里，删容器不影响卷。
> 但要注意**数据卷的位置**：`docker-compose.yml` 用的是命名卷 `qltools_data`，
> 如果你的旧容器是 `-v /some/dir:/app/data` 这种绑定挂载，两者不是同一份数据。
> 想沿用旧库，就把 compose 里的
> `- qltools_data:/app/data` 改成 `- /some/dir:/app/data`。

### 3.6 改完 compose 后数据「不见了」

**原因**：compose 默认用**命名卷** `qltools_data`，而手工容器可能用的是**绑定挂载目录**。
两者互不相通，换了挂载方式就等于换了一个空库。

**解决**：统一挂载方式（见 3.5 末尾）。数据库文件路径在 `.env` 的
`DB_NAME=/app/data/ql_tools_v2.db`，进容器就能看到：

```bash
docker exec qltools_v2 ls -la /app/data
```

---

## 四、接口调用异常

### 4.1 返回 `{"code": 50001, "msg": "接口不存在: ..."}`

路由或 HTTP 方法不对。核对方法是否与后端注册一致
（例如登出是 `POST /api/auth/logout`）。

### 4.2 成功码不是 200，怎么判断成功

统一响应体是：

```json
{ "code": 20000, "msg": "Success", "data": { } }
```

**成功码是 `20000`**，不是 `200`、也不是 `0`。HTTP 状态码基本都是 `200`，
业务成败一律看 `code` 字段。

### 4.3 `401` / 一直跳登录页

`access_token` 有效期 2 小时，前端会自动拿 `refresh_token`（30 天）换新的。
自动刷新失败通常意味着：

- `APP_SECRET` 被改过 —— JWT 签名密钥变了，旧 token 全部失效；
- 容器**重启过** —— token 是存在进程内 `gcache` 里的，重启即清空。

两种情况重新登录即可。

### 4.4 提交返回 `submitted_to = 0`

不是接口故障，是**没有可写入的目标**。逐一核对：

- 变量和面板**都要处于启用状态**（任一方禁用都会导致 0）；
- 变量是否已**绑定到面板**（变量详情里的面板绑定）；
- 面板的 `client_id` / `client_secret` 是否正确、青龙地址是否可达。

### 4.5 `Error` 只有两个字，没有任何信息

见上面的「2.1 点退出登录弹出 Error」。第一个动作永远是开 F12 看 Network 里的真实响应。

---

## 五、提交后存进去的值不对（正则配置）

### 5.1 正则填 `；`，客户输入 `1；2`，结果只存进了 `；`

**原因：「匹配正则」是「提取规则」，不是「校验规则」。**

代码在 `internal/service/open.go`，新建模式和更新模式都先走同一段（约 324 行）：

```go
if e.Regex != nil && *e.Regex != "" {
    re, err := regexp.Compile(*e.Regex)
    // ...
    matched := re.FindString(req.Value)   // ← 只取「第一个匹配到的片段」
    if matched == "" {
        return "变量值格式不符合要求"
    }
    req.Value = matched                   // ← 用这个片段「覆盖」整个提交值
}
```

`FindString` 返回的是**最左匹配到的子串**，不是你输入的全串。所以正则写 `；` 时：

```
FindString("1；2")  →  "；"
```

最后写进青龙面板的就是 `；`。同理，正则写 `\d+` 而客户输入 `abc123def`，存进去的会是 `123`。

**正确写法：让正则圈定「你想保存的完整内容」。**

| 你的目的 | 「匹配正则」该填 |
|---|---|
| 原样保存整串（含换行） | `^[\s\S]*$` |
| 必须包含 `；`，并且原样保存 | `^[\s\S]*；[\s\S]*$` |
| 只提取手机号 | `1[3-9]\d{9}` |
| 提取 cookie 里的 `pt_pin` | `pt_pin=[^;]+` |
| 不做任何提取/校验 | 留空 |

**四个容易踩的点：**

1. `^.+；.+$` 在**多行**输入上会失配——`.` 不匹配换行、`$` 只认整串结尾。需要跨行请用 `^[\s\S]*；[\s\S]*$`（或 Go 的 `(?s)` 前缀）。
2. 这是**子串匹配**，不是整串匹配：只要值里**任意一段**命中就放行，且放行的同时会把值裁剪成那一段。想让"整个值必须符合"，正则必须自带 `^...$` 并覆盖全部字符。
3. Go 的正则是 **RE2**，**不支持**反向引用（`\1`）、前瞻（`(?=...)`）、后顾（`(?<=...)`）。填了会在提交时报「正则表达式错误」。
4. 如果你的诉求是「校验一下格式，但值要原样保存」，当前版本没有独立的校验开关——用 `^[\s\S]*；[\s\S]*$` 这种"整体圈定"的正则即可等效做到。

### 5.2 更新模式：怎么配才能「已有则替换、没有则追加」

更新模式现在的语义是**把提交的值合并进同名变量**，不再整条覆盖（`updateExistingVariables`）：

1. 把同名变量的已有值按**多值分隔符**拆成若干**字段段**；
2. 从「客户提交的值」和「每个已有段」里各取一个**账号标识**；
3. 账号标识相同 → 该段**原位替换**成客户提交的完整值；
4. 账号标识都不同 → 在末尾**追加**客户提交的值；
5. 合并结果与原有值完全一致 → 不写入（重复提交不会产生重复内容）；
6. 只有**所有面板都没有这个变量名**时，才会新建。

> 从本版起，「**多值分隔符**」和「**账号字段分隔符**」都按变量单独配置，在后台变量编辑弹窗的「更新模式」下可见。

#### 一、账号标识怎么取（判定「是不是同一个账号」）

**优先用「账号字段分隔符」**：取每段中**第一个**该符号**之前**的内容作为账号标识。
只有它留空时，才退回用「**匹配正则[更新]**」提取。

这次反馈的场景：已有 `1;2`，再提交 `1;5`，结果却变成 `1;2&1;5`。
原因就是只配了「匹配正则[更新]」，而正则写成了整串圈定（如 `^[\s\S]*$`），于是 `1;2` 与 `1;5` 被当成两个完全不同的整串 → 判定不命中 → 追加。

**正确做法**：把「账号字段分隔符」填成 `;`（即 `1` 和 `2` 之间的那个符号）。

| 已有值 | 客户提交 | 取到的账号标识 | 结果 |
|--------|----------|----------------|------|
| `1;2` | `1;5` | 都是 `1` | 段 `1;2` 原位替换 → **`1;5`** ✅ |
| `1;2` | `3;9` | `1` vs `3` | 不命中 → 追加 → `1;2&3;9` |
| `1;2` | `1;2` | 都是 `1`，且内容没变 | **跳过写入** |

#### 二、多值分隔符怎么配（多账号之间用什么隔开）

| 你希望的存法 | 「多值分隔符」该填 |
|--------------|--------------------|
| 不关心，自动识别（原值有换行用换行，否则用 `&`） | 留空 |
| 强制用 `&` | `&` |
| 强制用换行 | `newline`（或 `换行`） |
| 强制用某个自定义符号（如 `,`） | `,` |

- **留空 = 自动**：原值含换行就按换行拆/拼，否则按 `&` 拆/拼；此模式下 `&` 和换行**都算**分隔符（与旧版本行为一致）。
- **一旦显式填写**：就**只按你填的符号**拆/拼，不再兼容另一种。
- 支持转义写法：`\n`、`\r`、`\t` 会被还原成换行、回车、制表符。

#### 三、只用「匹配正则[更新]」的老配法（仍然有效）

「账号字段分隔符」留空时，仍按正则提取账号标识，此时它应写成「**能唯一识别一段的标识**」，而不是整串：

| 场景 | `regex_update` 该填 |
|------|---------------------|
| 每段就是一个整体，按内容判重 | `[^&]+` |
| 每段形如 `pt_key=xxx;pt_pin=bob;`，按 `pt_pin` 判重 | `pt_pin=[^;]+` |
| 每段是纯数字 | `\d+` |
| 每段是 URL，按主机名判重 | `https?://[^/]+` |

排错日志：

```bash
docker compose logs -f --tail 200 qltools | grep -E "成功替换|成功追加|已包含相同内容|均无同名变量"
```

两个注意点：

- **判重的是「账号标识」不是「整串」**：标识相同但内容不同时会**整段替换**——这正是「更新」的意义。
- **只有第一个命中的段会被替换**：值里出现多个相同标识时，只动最靠前的那一个。

> ⚠️ **行为变更**：早期版本在未命中时会**整条覆盖**已有值或**静默退化成新建**（面板里冒出重复变量）；随后一版固定按 `&`/换行分段并用正则判重，但分隔符写死；**本版起「多值分隔符」与「账号字段分隔符」都可按变量单独配置**，两者留空时行为与上一版完全兼容。

---

## 六、命令速查

```bash
# 状态与日志
docker compose ps
docker compose logs -f --tail 100 qltools

# 校验编排文件（只解析，不启动）
docker compose config
docker compose config >/dev/null && echo "YAML OK"

# 看容器内实际生效的环境变量
docker exec qltools_v2 env | grep -E 'APP_|QLTOOLS_|DB_'

# 健康检查
curl -s localhost:1500/ping; echo

# 进容器看数据目录
docker exec -it qltools_v2 sh -c 'ls -la /app/data && cat /app/configs/config.yaml'

# 重建容器（改了 .env 或 compose 后）
docker compose up -d --force-recreate

# 升级镜像
docker compose pull && docker compose up -d

# 彻底重来（⚠️ -v 会删掉数据卷，库里的账号和配置全丢）
docker compose down -v
```

---

## 附：报告问题时请带上这些信息

```bash
docker compose ps
docker compose logs --tail 60 qltools
docker exec qltools_v2 env | grep -E 'APP_|QLTOOLS_|DB_'   # 贴之前把密码打码
docker compose config | head -40
```

浏览器侧则补上：F12 → Network 里那条失败请求的 **网址、方法、状态码、响应体**。
