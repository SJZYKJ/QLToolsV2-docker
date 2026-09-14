#!/usr/bin/env python3
"""
向 GitHub 仓库写入 Actions Secret（加密写入）。

GitHub 要求 Secret 值用仓库公钥做 libsodium sealed box 加密后上传，
不能明文 PUT，所以这里用 PyNaCl 处理。

用法:
    python gh-set-secret.py <owner/repo> <secret名> <secret值>
令牌从环境变量 GH_TOKEN 读取（不要作为命令行参数传入，避免出现在进程列表里）。

依赖: pip install pynacl
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
UA = "qltoolsv2-docker-bootstrap"


def die(msg, code=1):
    print("  !! " + msg, file=sys.stderr)
    sys.exit(code)


def api(token, url, method="GET", payload=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", UA)
    if payload is not None:
        req.data = json.dumps(payload).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            body = json.loads(body).get("message", body)
        except Exception:
            pass
        return e.code, {"message": body}


def main():
    if len(sys.argv) != 4:
        die("用法: gh-set-secret.py <owner/repo> <secret名> <secret值>")

    repo, name, value = sys.argv[1], sys.argv[2], sys.argv[3]
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        die("未设置环境变量 GH_TOKEN")

    try:
        from nacl import encoding, public
    except ImportError:
        die("缺少 PyNaCl，请先执行: pip install pynacl")

    status, data = api(token, "%s/repos/%s/actions/secrets/public-key" % (API, repo))
    if status != 200:
        die("获取仓库公钥失败 (HTTP %s): %s" % (status, data.get("message")))

    pub = public.PublicKey(data["key"].encode("utf-8"), encoding.Base64Encoder())
    sealed = public.SealedBox(pub).encrypt(value.encode("utf-8"))
    encrypted = base64.b64encode(sealed).decode("utf-8")

    status, data = api(
        token,
        "%s/repos/%s/actions/secrets/%s" % (API, repo, name),
        method="PUT",
        payload={"encrypted_value": encrypted, "key_id": data["key_id"]},
    )
    if status in (201, 204):
        print("  OK  已写入 Secret: %s" % name)
        return 0
    die("写入 Secret %s 失败 (HTTP %s): %s" % (name, status, data.get("message")))


if __name__ == "__main__":
    sys.exit(main())
