#!/usr/bin/env python3
"""KDS 本地冒烟：门店 shop_id=1，需本机 MySQL + Spring Boot :8080。"""
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"
SHOP_ID = 1
DEVICE_CODE = "KDS-SMOKE-TEST-01"
SCREEN_TAG = "meat_grill"


def http(method, path, body=None, headers=None):
    url = BASE + path
    data = None
    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def ok(j):
    return isinstance(j, dict) and j.get("code") in (0, 200, None) or j.get("code") == 0


def main():
    print("=== KDS smoke test shop_id=%s ===" % SHOP_ID)

    # 1) health: device login (needs stations — init via SQL or admin)
    st, j = http(
        "POST",
        "/kds/device/login",
        {
            "shop_id": SHOP_ID,
            "device_code": DEVICE_CODE,
            "screen_tag": SCREEN_TAG,
            "device_name": "冒烟测试屏",
        },
    )
    print("[login]", st, j)
    if not ok(j):
        print("FAIL: device login — 请先执行 init-five（见脚本说明）")
        return 1
    device = j.get("device") or {}
    token = device.get("device_token")
    if not token:
        print("FAIL: no device_token")
        return 1
    hdr = {"X-Kds-Device-Token": token}

    st, j = http("GET", "/kds/order/list?status=0", headers=hdr)
    print("[order/list pending]", st, "orders=", len(j.get("orders") or j.get("list") or []))

    st, j = http("GET", "/kds/stats/today", headers=hdr)
    print("[stats/today]", st, j.get("stats") or j)

    # recent detail from list or skip status test
    orders = j.get("orders") if isinstance(j.get("orders"), list) else None
    if st == 200 and j.get("stats"):
        pass
    st, j2 = http("GET", "/kds/order/list?status=pending", headers=hdr)
    orders = j2.get("orders") or []
    detail_id = None
    for o in orders:
        items = o.get("items") or o.get("goods_list") or []
        for it in items:
            did = it.get("detail_id") or it.get("id")
            if did:
                detail_id = did
                break
        if detail_id:
            break

    if detail_id:
        st, j = http(
            "POST",
            "/kds/item/status",
            {"detail_id": detail_id, "status": 1, "screen_tag": SCREEN_TAG},
            headers=hdr,
        )
        print("[item/status]", st, j)
    else:
        print("[item/status] SKIP — 无 pending 工单，可 admin repush 后重试")

    print("=== done ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
