#!/usr/bin/env bash
# ==============================================================================
# 一条龙：创建 GitHub 仓库 -> 推送代码 -> 写入 Docker Hub 凭据 -> 触发云端构建
#
# 为什么需要它：
#   本机没有独立的 Git（只有编辑器内置的），也没有 gh CLI / SSH 密钥，
#   所以「建仓库 + 推送 + 配 Secret + 触发 Actions」这几步用一个令牌一次做完。
#
# —— 用法 ——
#   export GH_TOKEN=ghp_xxxxxxxx            # GitHub 令牌，需 repo + workflow 权限
#   export DOCKERHUB_USERNAME=chungg
#   export DOCKERHUB_TOKEN=dckr_pat_xxxxxxxx
#   ./scripts/github-bootstrap.sh
#
# 可选环境变量：
#   GH_OWNER=你的用户名或组织名    默认从令牌所属账号推断
#   GH_REPO=仓库名                 默认 QLToolsV2-docker
#   GH_VISIBILITY=private|public   默认 private
#   SKIP_PUSH=1                    只配 Secret 和触发构建，不推送
#   SKIP_TRIGGER=1                 不触发构建
#
# —— 安全说明 ——
#   令牌只用于本次调用，推送时临时写进 git remote，推送完立刻改回干净地址。
#   脚本不会把令牌写进任何文件。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
ROOT="$(pwd)"

PY="${PYTHON_BIN:-python}"
PY_HELPER="$SCRIPT_DIR/gh-set-secret.py"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; NC=$'\033[0m'
info() { printf '%s==>%s %s\n' "$CYAN" "$NC" "$*"; }
ok()   { printf '%s  OK %s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%s  !! %s %s\n' "$YELLOW" "$NC" "$*"; }
die()  { printf '%s  错误: %s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
  exit 0
fi

# ---------------------------------------------------------------- 0. 前置检查
info "检查前置条件"

MISSING=""
[ -n "${GH_TOKEN:-}" ]                    || MISSING="$MISSING GH_TOKEN"
[ -n "${DOCKERHUB_USERNAME:-}" ]          || MISSING="$MISSING DOCKERHUB_USERNAME"
[ -n "${DOCKERHUB_TOKEN:-}" ]             || MISSING="$MISSING DOCKERHUB_TOKEN"
if [ -n "$MISSING" ]; then
  die "缺少环境变量：$MISSING
     示例：
       export GH_TOKEN=ghp_xxxxxxxx
       export DOCKERHUB_USERNAME=你的用户名
       export DOCKERHUB_TOKEN=dckr_pat_xxxxxxxx"
fi

command -v git >/dev/null 2>&1 || die "未找到 git 命令"
[ -d .git ] || die "当前目录不是 git 仓库：$ROOT"
[ -f Dockerfile ] || die "当前目录缺少 Dockerfile，请确认在项目根目录运行"
[ -f "$PY_HELPER" ] || die "缺少辅助脚本 $PY_HELPER"

# python 可执行文件探测（兼容 Windows 下的 py / python / python3）
if ! "$PY" -c "import nacl" >/dev/null 2>&1; then
  for cand in python3 py "C:/Users/Master丶ming/.workbuddy/binaries/python/envs/default/Scripts/python.exe"; do
    if "$cand" -c "import nacl" >/dev/null 2>&1; then PY="$cand"; break; fi
  done
fi
"$PY" -c "import nacl" >/dev/null 2>&1 \
  || die "当前 Python 缺少 PyNaCl，请执行：pip install pynacl"
ok "git / python(PyNaCl) / 项目文件齐备"

api() {  # api <METHOD> <path> [json]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -m 90 -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "User-Agent: qltoolsv2-docker-bootstrap" \
      -H "Content-Type: application/json" \
      -d "$body" \
      -w $'\n%{http_code}' "https://api.github.com$path"
  else
    curl -sS -m 90 -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "User-Agent: qltoolsv2-docker-bootstrap" \
      -w $'\n%{http_code}' "https://api.github.com$path"
  fi
}

jfield() { "$PY" -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',''))" 2>/dev/null; }

# ------------------------------------------------------------- 1. 令牌与账号
info "校验 GitHub 令牌"
resp="$(api GET /user)"
code="$(printf '%s' "$resp" | tail -n1)"
body="$(printf '%s' "$resp" | sed '$d')"
[ "$code" = "200" ] || die "令牌无效（HTTP $code）：$(printf '%s' "$body" | jfield message)"
LOGIN="$(printf '%s' "$body" | jfield login)"
ok "令牌有效，账号：$LOGIN"

OWNER="${GH_OWNER:-$LOGIN}"
REPO="${GH_REPO:-QLToolsV2-docker}"
FULL="$OWNER/$REPO"
VIS="${GH_VISIBILITY:-private}"
echo "     目标仓库：$FULL（$VIS）"

# --------------------------------------------------------------- 2. 建仓库
info "检查仓库是否存在"
resp="$(api GET "/repos/$FULL")"
code="$(printf '%s' "$resp" | tail -n1)"
if [ "$code" = "200" ]; then
  ok "仓库已存在，跳过创建"
elif [ "$code" = "404" ]; then
  if [ "$OWNER" = "$LOGIN" ]; then
    EP="/user/repos"
  else
    # 组织仓库；若令牌无权访问该组织，会在这里报错
    EP="/orgs/$OWNER/repos"
  fi
  info "仓库不存在，正在创建（$EP）"
  resp="$(api POST "$EP" "{\"name\":\"$REPO\",\"private\":$([ "$VIS" = "private" ] && echo true || echo false),\"description\":\"QLToolsV2 Docker 部署方案（内嵌源码 + 一键部署 + 云端构建）\",\"auto_init\":false,\"has_issues\":true}")"
  code="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  case "$code" in
    201) ok "仓库创建成功：https://github.com/$FULL" ;;
    422) warn "仓库已存在或名称冲突（HTTP 422），继续尝试推送" ;;
    *)   die "创建仓库失败（HTTP $code）：$(printf '%s' "$body" | jfield message)" ;;
  esac
else
  die "查询仓库失败（HTTP $code）：$(printf '%s' "$body" | jfield message)"
fi

# ----------------------------------------------------------------- 3. 推送
if [ "${SKIP_PUSH:-0}" = "1" ]; then
  warn "SKIP_PUSH=1，跳过推送"
else
  info "推送代码到 $FULL"
  CLEAN_URL="https://github.com/$FULL.git"
  AUTH_URL="https://x-access-token:${GH_TOKEN}@github.com/$FULL.git"

  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "$AUTH_URL"

  BRANCH="$(git branch --show-current 2>/dev/null || echo main)"
  [ -n "$BRANCH" ] || BRANCH=main
  echo "     分支：$BRANCH"
  echo "     提交：$(git log --oneline -1)"

  if git push -u origin "$BRANCH" 2>&1 | tail -6; then
    ok "推送完成"
  else
    git remote set-url origin "$CLEAN_URL" >/dev/null 2>&1 || true
    die "推送失败（常见原因：令牌缺少 workflow 权限，因为仓库含 .github/workflows）"
  fi
  # 立刻抹掉 remote 里的令牌
  git remote set-url origin "$CLEAN_URL"
  ok "remote 已改回不含令牌的地址：$CLEAN_URL"
fi

# --------------------------------------------------------------- 4. 配 Secret
info "写入 Actions Secrets"
GH_TOKEN="$GH_TOKEN" "$PY" "$PY_HELPER" "$FULL" DOCKERHUB_USERNAME "$DOCKERHUB_USERNAME"
GH_TOKEN="$GH_TOKEN" "$PY" "$PY_HELPER" "$FULL" DOCKERHUB_TOKEN "$DOCKERHUB_TOKEN"

# --------------------------------------------------------------- 5. 触发构建
if [ "${SKIP_TRIGGER:-0}" = "1" ]; then
  warn "SKIP_TRIGGER=1，未触发构建"
else
  info "触发云端构建（workflow_dispatch）"
  WF_FILE="docker-publish.yml"
  resp="$(api POST "/repos/$FULL/actions/workflows/$WF_FILE/dispatches" '{"ref":"main"}')"
  code="$(printf '%s' "$resp" | tail -n1)"
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    ok "已触发。构建日志：https://github.com/$FULL/actions"
  else
    warn "触发失败（HTTP $code），但推送到 main 也会自动触发构建"
    warn "手动触发：https://github.com/$FULL/actions/workflows/$WF_FILE"
  fi
fi

echo
printf '%s================ 完成 ================%s\n' "$CYAN" "$NC"
cat <<EOF
  仓库地址 : https://github.com/$FULL
  Actions  : https://github.com/$FULL/actions
  构建产物 : ${DOCKERHUB_USERNAME}/qltoolsv2:latest

  构建约需 5-10 分钟。之后在任意有 Docker 的机器上部署：

      cd 项目目录
      cp .env.example .env          # 填 IMAGE_REPO=${DOCKERHUB_USERNAME}/qltoolsv2
      ./scripts/deploy.sh --pull
EOF
