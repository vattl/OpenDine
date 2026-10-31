import json
import urllib.request

BASE = "https://zsq.wlhulian.com/api"
USER = __import__("os").environ.get("ZSQ_USERNAME", "13800138000")
PWD = __import__("os").environ.get("ZSQ_PASSWORD", "")

def http_json(url, method="GET", body=None, headers=None):
    h = headers or {}
    if body is not None:
        h.setdefault("Content-Type", "application/json")
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

login = http_json(BASE + "/store/staff/login", "POST", {
    "username": USER, "password": PWD, "type": 2, "loginType": 1, "code": ""
})
token = login["data"]["tokenHead"] + login["data"]["token"]
H = {"Authorization": token, "requestType": "pc", "Content-Type": "application/json"}

# list recent orders
lst = http_json(BASE + "/admin/open/order/getList?orderQueryType=1&status=0&pageNum=1&pageSize=5", headers=H)
print("list keys", lst.get("data", {}).keys() if isinstance(lst.get("data"), dict) else type(lst.get("data")))
items = (lst.get("data") or {}).get("list") or (lst.get("data") or {}).get("records") or []
if not items and isinstance(lst.get("data"), list):
    items = lst["data"]
print("count", len(items))
for it in items[:3]:
    oid = it.get("id")
    print("order", oid, it.get("orderId"), it.get("deliverySendStatus"), it.get("status"))
    detail = http_json(BASE + f"/open/order/{oid}", headers=H)
    d = detail.get("data") or {}
  # find fee related keys
    fee_keys = [k for k in d.keys() if any(x in k.lower() for x in ['fee', 'money', 'deduct', 'respon', 'liab', 'cancel', 'refund', 'compens', 'breach', 'duty', 'penalty', 'cost'])]
    print(" fee keys", fee_keys)
    for k in fee_keys:
        print(" ", k, d.get(k))
    parent = d.get("parentOrderNo") or d.get("parentOrderId")
    print(" parent", parent)
    if parent:
        for body in [
            {"parentOrderId": parent},
            {"parentOrderNo": parent},
            {"parentOrderId": str(parent)},
        ]:
            try:
                r = http_json(BASE + "/delivery/order/cancel", "POST", body, H)
                print(" cancel delivery", body, "->", json.dumps(r, ensure_ascii=False)[:600])
            except Exception as e:
                print(" cancel err", body, e)
