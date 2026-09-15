# NOTICE

## 第三方代码

本仓库的 [`src/`](src/) 目录包含第三方开源代码，其许可与归属如下：

| 项目 | 说明 |
|------|------|
| 许可协议 | **Apache License 2.0** —— 全文见 [`src/LICENSE`](src/LICENSE) |
| 源码快照 | 版本、文件数与原始出处记录在 [`src/.source-rev`](src/.source-rev) |
| 修改情况 | 源码文件未作改动；仅移除了原有的一个 `.gitignore`（其 `dist/` 规则会误排除前端产物），并新增了本快照记录文件 |

Apache-2.0 允许自由使用、修改与再分发，需保留许可证与版权声明。
将构建产物发布到镜像仓库时请一并遵守该许可。

## 本项目自有内容

除 `src/` 之外的其余文件——`Dockerfile`、`entrypoint.sh`、
`docker-compose*.yml`、`scripts/`、`examples/`、`configs/` 及各文档——
为本项目自有内容。
