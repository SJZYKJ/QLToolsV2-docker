# 上游源码说明（`upstream/`）

本仓库把上游源码**内嵌**在 `upstream/` 目录，目的是让镜像构建**不再依赖 GitHub 的可达性** —— 即使上游仓库被删除、归档或网络不通，本仓库依然能独立构建出完全相同的镜像。

| 项目 | 值 |
|---|---|
| 上游仓库 | https://github.com/nuanxinqing123/QLToolsV2 |
| 获取方式 | GitHub tarball（codeload） |
| 锁定提交 | `00d5328881ac0e7ef8bc13842979a028b5a8c910` |
| 获取日期 | 2026-09-14 |
| 文件总数 | 306 |
| 前端产物 | `upstream/web/dist`（158 个文件，已入库，无需 Node 构建） |
| 许可证 | Apache License 2.0（见 `upstream/LICENSE`） |
| 上游状态 | 已废弃 / 停止维护，本仓库仅作只读使用 |

## 为什么内嵌而不是构建时 clone

原方案在 `Dockerfile` 里 `git clone` 上游仓库，存在三个问题：

1. **可用性风险** —— 上游是废弃项目，随时可能被归档或删除，届时构建直接失败。
2. **可复现性差** —— `QLTOOLS_REF=master` 每次构建拉到的代码都可能不同，镜像不可复现。
3. **速度慢** —— 每次构建都要重新克隆 300+ 文件。

内嵌源码 + 锁定提交后，构建结果**完全可复现**，且与上游是否存活无关。

## 许可证与合规

上游采用 **Apache License 2.0**，允许自由使用、修改和再分发，需要满足：

- 保留 `upstream/LICENSE` 文件（已随源码保留）；
- 保留原始版权声明；
- 若你修改了源码，需注明已修改。

因此**将构建好的镜像推送到你自己的 Docker Hub 是合规的**。建议在镜像描述中注明来源：

> Based on QLToolsV2 (https://github.com/nuanxinqing123/QLToolsV2), Apache-2.0.

## 如何更新上游源码

```bash
./scripts/fetch-upstream.sh                 # 拉取 master 最新
./scripts/fetch-upstream.sh --ref v2.1.0    # 指定分支或 tag
./scripts/fetch-upstream.sh --sha <commit>  # 锁定到具体提交（推荐）
./scripts/fetch-upstream.sh --from ./pkg.tar.gz   # 用本地离线包（无网络时）
```

更新后请重新构建镜像；`upstream/.upstream-rev` 记录了当前锁定的版本信息。
