#!/usr/bin/env bash
# ==============================================================================
# 向 QLToolsV2 提交一条环境变量数据到已绑定的青龙面板
#
#   POST /api/open/submit  —— 公开接口，无需登录，但带令牌桶限速
#   请求体：{"env_id": <int>, "value": "<string>", "key": "<可选>", "remarks": "<可选>"}
#   响应体：{"code":20000,"msg":"Success","data":{"success":true,...,"submitted_to":N}}
#           —— 成功码是 20000（internal/pkg/response/code.go: CodeSuccess）
#
# 前置条件：已在 Web 后台创建变量(env)并绑定到「启用状态」的青龙面板。
# 依赖：curl 与 python3（python3 仅用于安全地拼 JSON 与美化输出）
# ==============================================================================
set -euo pipefail

BASE_URL="${QLTOOLS_URL:-http://127.0.0.1:1500}"
ENV_ID="${ENV_ID:?请设置 ENV_ID（变量ID，后台变量列表可见）}"
VALUE="${VALUE:?请设置 VALUE（要写入青龙的变量值）}"
KEY="${KEY:-}"           # 变量开启了 KEY 校验（enable_key=true）时必填
REMARKS="${REMARKS:-}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "!! 需要 python3 用于拼装 JSON（避免变量值里的引号破坏请求体）" >&2
  exit 1
fi

# 用 python3 生成 JSON，保证 value 中的引号/换行/中文被正确转义
JSON=$(ENV_ID="$ENV_ID" VALUE="$VALUE" KEY="$KEY" REMARKS="$REMARKS" python3 -c '
import json, os
body = {"env_id": int(os.environ["ENV_ID"]), "value": os.environ["VALUE"]}
if os.environ.get("KEY"):
    body["key"] = os.environ["KEY"]
if os.environ.get("REMARKS"):
    body["remarks"] = os.environ["REMARKS"]
print(json.dumps(body, ensure_ascii=False))
')

echo ">> 提交数据到 ${BASE_URL}/api/open/submit（env_id=${ENV_ID}）"

RESP=$(curl -sS -X POST "${BASE_URL}/api/open/submit" \
  -H "Content-Type: application/json" \
  --data-binary "$JSON")

echo "$RESP" | python3 -m json.tool 2>/dev/null || { echo "$RESP"; exit 1; }

# 校验状态码：20000 表示成功
CODE=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code"))' 2>/dev/null || echo "")
if [ "$CODE" != "20000" ]; then
  echo "!! 提交失败：code=${CODE}（成功码应为 20000）" >&2
  exit 1
fi

echo ">> 提交成功。若 submitted_to 为 0，请检查变量是否已启用、是否绑定了启用状态的面板。"
