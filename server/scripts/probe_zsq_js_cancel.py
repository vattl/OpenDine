import re
import urllib.request

c = "static/js/chunk-20822747.276b0d32.js"
s = urllib.request.urlopen("https://zsq.wlhulian.com/" + c, timeout=30).read().decode("utf-8", "ignore")
# find all Object(x)({ patterns near cancel
for m in re.finditer(r'Object\(\w\["a"\]\)\(\{url:"/delivery/order/cancel/v2"', s):
    print(s[max(0,m.start()-100):m.start()+200])
# find usages of function x (cancel v2) - exported as x in module
idx = s.find('function x(e){return Object(r["a"])({url:"/delivery/order/cancel/v2"')
print('export block', s[idx:idx+120])
# search for ",x(" or "(x(" in file
for pat in [',x({', 'Object(r["x"])(', '"x"']:
    pass
# brute: find cancel/v2 callers by searching backwards from cancel/v2 for handle
pos = 0
while True:
    j = s.find('cancel/v2', pos)
    if j < 0: break
    pos = j + 1
# search other file chunk-13de for open/delivery/order/cancel usage
c2 = "static/js/chunk-13de3d08.fb21c69d.js"
s2 = urllib.request.urlopen("https://zsq.wlhulian.com/" + c2, timeout=30).read().decode("utf-8", "ignore")
for kw in ['open/delivery/order/cancel"', 'cancel/message', 'deduct', 'parentOrderId', 'cancelReason']:
    if kw in s2:
        i = s2.find(kw)
        print('\n13de', kw, s2[max(0,i-200):i+400].replace('\n',' ')[:550])
