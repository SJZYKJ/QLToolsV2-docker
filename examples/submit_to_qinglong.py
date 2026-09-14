#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QLToolsV2 一键脚本：确保面板存在 -> 确保变量存在并启用 -> 绑定面板 -> 提交数据到青龙

接口契约全部按上游源码核对（nuanxinqing123/QLToolsV2@master）：
  * 统一响应体为 {"code": 20000, "msg": "Success", "data": {...}}
    成功码是 20000，不是 200 / 0
    （internal/pkg/response/code.go: CodeSuccess ResCode = 20000）
  * 管理类接口（panel / env）需要 JWT，请求头 Authorization: Bearer <access_token>
  * 提交接口 POST /api/open/submit 免登录，但带更严格的令牌桶限速
  * 分页列表数据在 data.list，总数在 data.total

两种获取 Token 的方式（按顺序自动选择）：
  1) 直接给 QLTOOLS_TOKEN          —— 从浏览器登录后 F12 复制 access_token
  2) 给 QLTOOLS_USERNAME / QLTOOLS_PASSWORD
     —— 脚本会拉取算术验证码保存为 captcha.png，你在终端输入答案后自动登录
        （登录与注册都必须通过验证码，这是上游 auth 控制器的强制要求）

环境变量：
  QLTOOLS_URL        QLToolsV2 地址，默认 http://127.0.0.1:1500
  QLTOOLS_TOKEN      JWT access_token（二选一）
  QLTOOLS_USERNAME   登录用户名（二选一）
  QLTOOLS_PASSWORD   登录密码（二选一）
  QL_PANEL_URL       青龙面板地址，如 http://1.2.3.4:5700
  QL_PANEL_NAME      面板在 QLTools 中的显示名，默认 qinglong-1
  QL_CLIENT_ID       青龙 Open API client_id
  QL_CLIENT_SECRET   青龙 Open API client_secret
  ENV_NAME           变量名，默认 JD_COOKIE
  ENV_VALUE          要提交到青龙的变量值（必填）
  ENV_QUANTITY       该变量可承载的负载数量，默认 10
  ENV_MODE           模式，默认 1
  ENV_CDK_LIMIT      单次消耗卡密额度，默认 0
  ENV_ENABLE_KEY     是否启用 KEY(卡密) 校验，默认 false
                     —— 控制 KEY 校验的是这个字段，不是 cdk_limit
  ENV_AUTO_ENABLE    提交到青龙后是否自动启用该变量，默认 true
  ENV_REMARKS        变量备注，可选
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("QLTOOLS_URL", "http://127.0.0.1:1500").rstrip("/")
TOKEN = os.environ.get("QLTOOLS_TOKEN", "")
USERNAME = os.environ.get("QLTOOLS_USERNAME", "")
PASSWORD = os.environ.get("QLTOOLS_PASSWORD", "")

PANEL_URL = os.environ.get("QL_PANEL_URL", "")
PANEL_NAME = os.environ.get("QL_PANEL_NAME", "qinglong-1")
CLIENT_ID = os.environ.get("QL_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("QL_CLIENT_SECRET", "")

ENV_NAME = os.environ.get("ENV_NAME", "JD_COOKIE")
ENV_VALUE = os.environ.get("ENV_VALUE", "")
QUANTITY = int(os.environ.get("ENV_QUANTITY", "10"))
MODE = int(os.environ.get("ENV_MODE", "1"))
CDK_LIMIT = int(os.environ.get("ENV_CDK_LIMIT", "0"))
ENABLE_KEY = os.environ.get("ENV_ENABLE_KEY", "false").lower() in ("1", "true", "yes")
AUTO_ENABLE = os.environ.get("ENV_AUTO_ENABLE", "true").lower() in ("1", "true", "yes")
ENV_REMARKS = os.environ.get("ENV_REMARKS", "") or None

CODE_SUCCESS = 20000


def _req(method, path, body=None, token=None):
    """发起请求，返回 (http_status, 解析后的 JSON)。"""
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        method=method,
    )
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            return exc.code, json.loads(raw)
        except Exception:
            return exc.code, {"code": None, "msg": raw}
    except Exception as exc:  # noqa: BLE001
        return 0, {"code": None, "msg": str(exc)}


def _ok(resp):
    return resp.get("code") == CODE_SUCCESS


def _fail(action, resp):
    print(f"[{action}] 失败：code={resp.get('code')} msg={resp.get('msg')}")
    sys.exit(1)


def login_with_captcha():
    """拉取算术验证码 -> 人工识别 -> 登录换取 access_token。"""
    status, resp = _req("GET", "/api/auth/captcha")
    if status != 200 or not _ok(resp):
        _fail("验证码", resp)

    data = resp.get("data") or {}
    captcha_id = data.get("captcha_id")
    b64 = (data.get("captcha_base64") or "").split(",", 1)[-1]
    path = os.path.join(os.getcwd(), "captcha.png")
    with open(path, "wb") as fp:
        fp.write(base64.b64decode(b64))
    print(f"[登录] 验证码已保存到 {path}，请打开查看算术题结果")

    code = input("[登录] 请输入验证码答案: ").strip()
    status, resp = _req(
        "POST",
        "/api/auth/login",
        {
            "username": USERNAME,
            "password": PASSWORD,
            "captcha_id": captcha_id,
            "captcha_code": code,
        },
    )
    if not _ok(resp):
        _fail("登录", resp)
    print("[登录] 成功")
    return resp["data"]["access_token"]


def ensure_panel(token):
    status, resp = _req("GET", "/api/panel/list?page=1&page_size=100", token=token)
    if not _ok(resp):
        _fail("面板列表", resp)
    for panel in (resp.get("data") or {}).get("list") or []:
        if panel.get("url") == PANEL_URL:
            print(f"[面板] 已存在：id={panel['id']} name={panel['name']}")
            return panel["id"]

    status, resp = _req(
        "POST",
        "/api/panel/create",
        {
            "name": PANEL_NAME,
            "url": PANEL_URL,
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "is_enable": True,
        },
        token=token,
    )
    if not _ok(resp):
        _fail("创建面板", resp)
    pid = (resp.get("data") or {}).get("id")
    print(f"[面板] 创建成功：id={pid}")
    return pid


def ensure_env(token):
    status, resp = _req("GET", "/api/env/list?page=1&page_size=100", token=token)
    if not _ok(resp):
        _fail("变量列表", resp)
    for env in (resp.get("data") or {}).get("list") or []:
        if env.get("name") == ENV_NAME:
            print(f"[变量] 已存在：id={env['id']} name={env['name']} 启用={env.get('is_enable')}")
            if not env.get("is_enable"):
                _req("POST", "/api/env/toggle-status", {"id": env["id"], "is_enable": True}, token=token)
                print("[变量] 已重新启用")
            return env["id"]

    # AddEnvRequest 中 quantity / mode / cdk_limit 均为必填
    status, resp = _req(
        "POST",
        "/api/env/create",
        {
            "name": ENV_NAME,
            "remarks": ENV_REMARKS,
            "quantity": QUANTITY,
            "mode": MODE,
            "cdk_limit": CDK_LIMIT,
            "enable_key": ENABLE_KEY,
            "is_auto_env_enable": AUTO_ENABLE,
        },
        token=token,
    )
    if not _ok(resp):
        _fail("创建变量", resp)
    eid = (resp.get("data") or {}).get("id")
    # 新建变量默认可能是禁用状态，这里显式启用
    _req("POST", "/api/env/toggle-status", {"id": eid, "is_enable": True}, token=token)
    print(f"[变量] 创建成功并启用：id={eid}")
    return eid


def bind_and_submit(token, env_id, panel_id):
    status, resp = _req("POST", "/api/env/panels", {"env_id": env_id, "panel_ids": [panel_id]}, token=token)
    if not _ok(resp):
        _fail("绑定面板", resp)
    print(f"[绑定] env {env_id} -> panel {panel_id} 完成")

    body = {"env_id": env_id, "value": ENV_VALUE, "remarks": "by script"}
    status, resp = _req("POST", "/api/open/submit", body)
    if not _ok(resp):
        _fail("提交数据", resp)
    data = resp.get("data") or {}
    print(
        f"[提交] 成功：submitted_to={data.get('submitted_to')} "
        f"remaining_cdk={data.get('remaining_cdk')} msg={resp.get('msg')}"
    )
    if not data.get("submitted_to"):
        print("       提示：submitted_to 为 0 通常是变量未启用，或绑定的面板处于禁用状态。")


def main():
    global TOKEN
    if not TOKEN:
        if USERNAME and PASSWORD:
            TOKEN = login_with_captcha()
        else:
            print("缺少鉴权信息：请设置 QLTOOLS_TOKEN，或同时设置 QLTOOLS_USERNAME 与 QLTOOLS_PASSWORD。")
            sys.exit(1)

    missing = [k for k, v in {
        "QL_PANEL_URL": PANEL_URL,
        "QL_CLIENT_ID": CLIENT_ID,
        "QL_CLIENT_SECRET": CLIENT_SECRET,
        "ENV_VALUE": ENV_VALUE,
    }.items() if not v]
    if missing:
        print("缺少必填环境变量：" + ", ".join(missing))
        sys.exit(1)

    panel_id = ensure_panel(TOKEN)
    env_id = ensure_env(TOKEN)
    bind_and_submit(TOKEN, env_id, panel_id)


if __name__ == "__main__":
    main()
