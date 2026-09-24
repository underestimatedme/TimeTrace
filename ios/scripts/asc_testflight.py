#!/usr/bin/env python3
"""TestFlight 小工具：查看构建处理状态、把构建加进测试组。

依赖 App Store Connect API 密钥（Users and Access → Integrations → App Store Connect API），
通过环境变量传入，不写进仓库：

    ASC_KEY_ID      密钥 ID，例如 ABC123DEFG
    ASC_ISSUER_ID   Issuer ID（UUID）
    ASC_KEY_PATH    AuthKey_<KEY_ID>.p8 的路径

用法：
    asc_testflight.py status                     # 构建列表 + 测试组
    asc_testflight.py add-build 2026092303 内部测试  # 把某构建加进名为「内部测试」的组

依赖：pip install pyjwt cryptography
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("ASC_BUNDLE_ID", "com.atlaspaces.timetrace")


def token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    with open(os.environ["ASC_KEY_PATH"], "rb") as fh:
        private_key = fh.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    req = urllib.request.Request(API + path, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        sys.exit(f"{method} {path} -> HTTP {err.code}\n{detail}")


def app_id() -> str:
    apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"App Store Connect 里没有 bundle id 为 {BUNDLE_ID} 的 App 记录")
    return apps[0]["id"]


def builds(app: str):
    path = (f"/v1/builds?filter[app]={app}&sort=-uploadedDate&limit=20"
            "&include=preReleaseVersion,buildBetaDetail"
            "&fields[builds]=version,processingState,uploadedDate,expired,preReleaseVersion,buildBetaDetail"
            "&fields[preReleaseVersions]=version"
            "&fields[buildBetaDetails]=internalBuildState,externalBuildState")
    res = call("GET", path)
    included = {(i["type"], i["id"]): i for i in res.get("included", [])}
    rows = []
    for b in res["data"]:
        rel = b["relationships"]
        pre = rel.get("preReleaseVersion", {}).get("data")
        detail = rel.get("buildBetaDetail", {}).get("data")
        marketing = included.get(("preReleaseVersions", pre["id"]))["attributes"]["version"] if pre else "?"
        states = included.get(("buildBetaDetails", detail["id"]), {}).get("attributes", {}) if detail else {}
        rows.append({
            "id": b["id"],
            "version": f'{marketing} ({b["attributes"]["version"]})',
            "build": b["attributes"]["version"],
            "processing": b["attributes"]["processingState"],
            "uploaded": b["attributes"]["uploadedDate"],
            "expired": b["attributes"]["expired"],
            "internal": states.get("internalBuildState"),
            "external": states.get("externalBuildState"),
        })
    return rows


def groups(app: str):
    res = call("GET", f"/v1/betaGroups?filter[app]={app}&include=builds&fields[builds]=version")
    out = []
    for g in res["data"]:
        build_ids = [d["id"] for d in g["relationships"].get("builds", {}).get("data", [])]
        testers = call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?fields[betaTesters]=email&limit=200")["data"]
        out.append({
            "id": g["id"],
            "name": g["attributes"]["name"],
            "internal": g["attributes"]["isInternalGroup"],
            "builds": build_ids,
            "testers": [t["attributes"].get("email") for t in testers],
        })
    return out


def cmd_status():
    app = app_id()
    print(f"App id {app} · bundle {BUNDLE_ID}\n")
    print("构建：")
    rows = builds(app)
    for r in rows:
        flags = " expired" if r["expired"] else ""
        print(f"  {r['version']:<22} {r['processing']:<12} internal={r['internal']} external={r['external']}"
              f"  uploaded {r['uploaded']}{flags}")
    if not rows:
        print("  （没有任何构建）")
    print("\n测试组：")
    by_id = {r["id"]: r["version"] for r in rows}
    for g in groups(app):
        kind = "内部" if g["internal"] else "外部"
        names = [by_id.get(b, b) for b in g["builds"]] or ["（无构建）"]
        print(f"  [{kind}] {g['name']}  构建: {', '.join(names)}  测试员 {len(g['testers'])} 人")


def cmd_add_build(build_number: str, group_name: str):
    app = app_id()
    match = [r for r in builds(app) if r["build"] == build_number]
    if not match:
        sys.exit(f"没有构建号 {build_number} 的构建，先跑 status 看看")
    build = match[0]
    if build["processing"] != "VALID":
        sys.exit(f"构建 {build['version']} 还在 {build['processing']}，处理完成（VALID）后再加")
    grp = [g for g in groups(app) if g["name"] == group_name]
    if not grp:
        sys.exit(f"没有名为「{group_name}」的测试组，先跑 status 看看")
    group = grp[0]
    if build["id"] in group["builds"]:
        print(f"{build['version']} 已在「{group_name}」里，无需重复添加")
        return
    call("POST", f"/v1/betaGroups/{group['id']}/relationships/builds",
         {"data": [{"type": "builds", "id": build["id"]}]})
    print(f"已把 {build['version']} 加进「{group_name}」（{'内部' if group['internal'] else '外部'}组）")
    if not group["internal"]:
        print("外部组的构建还要通过 Beta 审核才会推送给测试员")


def main(argv):
    if len(argv) >= 2 and argv[1] == "status":
        cmd_status()
    elif len(argv) == 4 and argv[1] == "add-build":
        cmd_add_build(argv[2], argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
