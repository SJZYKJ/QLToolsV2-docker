# src/ —— 服务端源码

本目录是 QLToolsV2 的 Go 服务端源码，也是 Docker 镜像构建的**唯一**源码来源
（见根目录 [`Dockerfile`](../Dockerfile) 与 [`.dockerignore`](../.dockerignore)）。

模块路径：`github.com/SJZYKJ/QLToolsV2-docker`

| 目录 | 说明 |
|------|------|
| `cmd/` | 程序入口（`main.go`） |
| `internal/app/` | 启动装配：配置、日志、路由、初始化（`initializer/`） |
| `internal/controller/` | HTTP 控制器 |
| `internal/service/` | 业务逻辑 |
| `internal/data/` | Ent ORM 客户端与生成代码（`ent/`） |
| `internal/schema/` | 请求 / 响应结构体 |
| `internal/pkg/` | 内部库：青龙 API、插件引擎、HTTP 客户端 |
| `internal/middleware/` | JWT、限速、日志、恢复中间件 |
| `internal/utils/` | 工具函数 |
| `docs/` | Swagger 文档，被 `router.go` 空白导入，**不可删除** |
| `web/` | 前端产物，通过 `//go:embed all:dist` 打进二进制 |
| `configs/` | 配置样例 |

架构与部署说明请看根目录的 [README.md](../README.md)、
[DEPLOY.md](../DEPLOY.md) 与 [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)。

## 本地构建

需要 Go 1.24 或更高版本：

```bash
go build -o bin/QLToolsV2 ./cmd     # 或 make build
go run ./cmd                        # 或 make run
```

## 修改数据模型后重新生成 Ent 代码

数据模型定义在 `internal/data/ent/schema/*.go`。改动 schema 后**必须**重新生成
`internal/data/ent/` 下的代码，否则会编译失败或运行期报字段不存在：

```bash
make gen
```

等价于：

```bash
cd internal/data/ent && go generate ./...
```

> ⚠️ 生成代码里的 `runtime.go` 用**数组下标**（`envFields[11]` 这种）取字段描述符，
> 在 schema 中间插入字段会让后续下标整体后移，导致运行期类型断言 panic。
> 用 `ent generate` 生成的代码不会有这个问题；如果是手工改动，务必同步核对下标。
