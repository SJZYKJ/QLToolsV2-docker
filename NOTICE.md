# NOTICE

## 第三方代码与许可

本仓库 [`src/`](src/) 目录内的服务端源码，基于一个采用 **Apache License 2.0**
的开源项目。许可全文见 [`src/LICENSE`](src/LICENSE)，原始版权与许可声明保留其中、
未作改动。

本仓库在该源码基础上做过的改动：

- 统一模块路径为本仓库地址：`github.com/SJZYKJ/QLToolsV2-docker`
- 移除了随源码带入、与本仓库部署方式无关的第三方 CI 配置、发布配置与模板文件
- 修正了由数据模型字段变更引起的 Ent 生成代码，并调整了若干业务逻辑

Apache-2.0 允许自由使用、修改与再分发，但要求保留许可证与版权声明。
把构建产物发布到镜像仓库时，请一并遵守该许可。

## 本项目自有内容

除 `src/` 之外的其余文件——`Dockerfile`、`entrypoint.sh`、`docker-compose*.yml`、
`.github/workflows/`、`scripts/`、`examples/`、`configs/` 及各文档——为本项目自有内容。
