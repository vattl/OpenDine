#!/usr/bin/env python3
"""
线上支付模块冒烟 + 回归探针（T1/T2 部分自动化）。

前置：
  - Spring Boot :8080
  - 已执行 docs/db_migration_payment_module.sql
  - payment.use-facade=true（默认）

完整矩阵见 docs/payment_module_upgrade_development_plan.md §9（T3–T15 需人工/沙箱）。
"""
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"
SHOP_ID = 1


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


def unwrap(j):
    if isinstance(j, dict) and "data" in j and isinstance(j["data"], dict):
        return j["data"]
    return j if isinstance(j, dict) else {}


def main():
    print("=== payment smoke / regression probe shop_id=%s ===" % SHOP_ID)
    failed = 0
    hdr = {"X-Shop-Id": str(SHOP_ID)}

    st, j = http("GET", "/config/payment-capabilities?shop_id=%s" % SHOP_ID)
    print("[T2 capabilities]", st, j)
    cap = unwrap(j)
    if st != 200:
        print("FAIL: capabilities HTTP")
        return 1
    for key in ("onlinePayEnabled", "disabledMessage", "channels"):
        if key not in cap and key not in j:
            print("WARN: missing field", key)
    print("  onlinePayEnabled=", cap.get("onlinePayEnabled", j.get("onlinePayEnabled")))

    # T1 探针：关线上支付时三接口应 40201（此处仅验证接口可达；关开关需后台或 SQL）
    for name, path, body in [
        ("getPrepayId", "/order/getPrepayId", {"orderNo": "ORD000000000000", "openid": ""}),
        ("payByBalance", "/order/payByBalance", {"orderNo": "ORD000000000000", "openid": "x"}),
        ("recharge", "/order/recharge", {"openid": "smoke_openid_missing"}),
    ]:
        st, j = http("POST", path, body, hdr)
        code = j.get("code") if isinstance(j, dict) else None
        print("[%s route] HTTP=%s code=%s msg=%s" % (name, st, code, j.get("msg") if isinstance(j, dict) else ""))
        if st != 200:
            failed += 1
        if code == 40201:
            print("  (T1) online pay disabled — expected when online_pay_enabled=0")

    if failed:
        print("FAIL: %s HTTP check(s)" % failed)
        return 1
    print("OK: Facade 路由与 capabilities 可达")
    print("Manual: T3–T15 见 server/docs/payment_module_upgrade_development_plan.md §9")
    return 0


if __name__ == "__main__":
    sys.exit(main())
