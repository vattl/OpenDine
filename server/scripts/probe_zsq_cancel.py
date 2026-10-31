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
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode())

login = http_json(BASE + "/store/staff/login", "POST", {
    "username": USER, "password": PWD, "type": 2, "loginType": 1, "code": ""
})
token = login["data"]["tokenHead"] + login["data"]["token"]
H = {"Authorization": token, "requestType": "pc", "Content-Type": "application/json"}
open_id = 43788273

candidates = [
    ("POST", "/open/order/cancel", {"id": open_id}),
    ("POST", "/open/order/cancel", {"openOrderId": open_id}),
    ("POST", "/open/order/cancel", {"orderId": open_id}),
    ("POST", "/open/order/cancelOrder", {"id": open_id}),
    ("POST", "/delivery/order/cancel", {"openOrderId": open_id}),
    ("GET", f"/open/order/cancel/{open_id}", None),
]
for method, path, body in candidates:
    url = BASE + path
    r = http_json(url, method, body, H)
    print(method, path, "->", json.dumps(r, ensure_ascii=False)[:800])
    print("---")
