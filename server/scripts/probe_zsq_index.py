import re
import urllib.request

for path in ["/", "/index.html", "/app.js", "/static/js/app.js"]:
    try:
        b = urllib.request.urlopen("https://zsq.wlhulian.com" + path, timeout=15).read().decode("utf-8", "ignore")
        print(path, "len", len(b))
        js = re.findall(r"[\w./-]+\.js", b)
        print(" refs", js[:15])
    except Exception as e:
        print(path, e)
