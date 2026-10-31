import json
import urllib.parse
import urllib.request

BASE = "https://zsq.wlhulian.com/api"

def http_json(url, method="GET", body=None, headers=None):
    h = headers or {}
    if body is not None:
        h.setdefault("Content-Type", "application/json")
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

login = http_json(BASE + "/store/staff/login", "POST", {
    "username": __import__("os").environ.get("ZSQ_USERNAME", "13800138000"), "password": __import__("os").environ.get("ZSQ_PASSWORD", ""), "type": 2, "loginType": 1, "code": ""
})
H = {"Authorization": login["data"]["tokenHead"] + login["data"]["token"], "requestType": "pc", "Content-Type": "application/json"}

# create + try cancel message on undispatched
shops = http_json(BASE + "/open/order/address", headers=H)["data"]
shop = next((s for s in shops if s.get("isDefault") == 1), shops[0])
city = urllib.parse.quote("\u6c55\u95e8\u5e02")
kw = urllib.parse.quote("\u6c99\u576a\u8857\u9053\u5927\u9e4f\u8def")
tip = http_json(BASE + f"/address/v2/input-tips?city={city}&keywords={kw}", headers=H)["data"][0]
payload = {"type": 1, "fromAddressId": shop["id"], "goodType": shop.get("industryType") or 1,
    "toReceiverName": "t", "toMobile": "13800138001", "toAddress": tip.get("address") or "a",
    "toAddressDetail": "d", "toLatitude": tip["location"]["lat"], "toLongitude": tip["location"]["lng"],
    "productName": "x", "productAmount": "50", "productCount": 1, "weight": 3, "orderRemark": "", "expectTime": "", "orderType": 1}
oid = http_json(BASE + "/open/order/create", "POST", payload, H)["data"]["id"]
for path, method, body in [
    (f"/open/delivery/order/cancel/message/{oid}", "POST", None),
    (f"/delivery/order/cancelPrompt/{oid}", "GET", None),
]:
    r = http_json(BASE + path, method, body, H)
    print(path, json.dumps(r, ensure_ascii=False))
