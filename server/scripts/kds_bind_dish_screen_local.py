#!/usr/bin/env python3
"""Local bind dishes to KDS screen (same logic as POST /admin/kds/dish-screen/bind)."""
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime

try:
    import pymysql
except ImportError:
    pymysql = None

DB = dict(host="127.0.0.1", user="db_diancan", password=__import__("os").environ["DB_PASSWORD"], database="db_diancan", charset="utf8mb4")
BASE = "http://127.0.0.1:8080"
SHOP_ID = 1
SCREEN_TAG = "meat_grill"
DISH_IDS = [17, 18, 22, 20, 100, 79, 71, 19, 23, 101, 21, 27, 82, 26, 44, 81, 98, 84, 74, 83, 25, 24]


def bind_via_db():
    conn = pymysql.connect(**DB)
    cur = conn.cursor(pymysql.cursors.DictCursor)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    inserted = updated = skipped = 0
    missing = []
    for dish_id in DISH_IDS:
        cur.execute("SELECT id, name FROM t_dish WHERE id=%s", (dish_id,))
        if not cur.fetchone():
            missing.append(dish_id)
            continue
        cur.execute(
            "SELECT id, screen_tag FROM t_kds_dish_screen WHERE shop_id=%s AND dish_id=%s",
            (SHOP_ID, dish_id),
        )
        row = cur.fetchone()
        if row is None:
            cur.execute(
                "INSERT INTO t_kds_dish_screen (shop_id, dish_id, screen_tag, created_at) "
                "VALUES (%s, %s, %s, %s)",
                (SHOP_ID, dish_id, SCREEN_TAG, now),
            )
            inserted += 1
        elif row["screen_tag"] != SCREEN_TAG:
            cur.execute(
                "UPDATE t_kds_dish_screen SET screen_tag=%s, updated_at=%s WHERE id=%s",
                (SCREEN_TAG, now, row["id"]),
            )
            updated += 1
        else:
            skipped += 1
    conn.commit()
    cur.execute(
        """
        SELECT ds.dish_id, d.name, d.sorting
        FROM t_kds_dish_screen ds
        JOIN t_dish d ON d.id = ds.dish_id
        WHERE ds.shop_id=%s AND ds.screen_tag=%s
        ORDER BY d.sorting, ds.dish_id
        """,
        (SHOP_ID, SCREEN_TAG),
    )
    rows = cur.fetchall()
    conn.close()
    return {
        "inserted": inserted,
        "updated": updated,
        "skipped": skipped,
        "missing": missing,
        "list": rows,
    }


def bind_via_api(token):
    body = {"screenTag": SCREEN_TAG, "dishIds": DISH_IDS}
    req = urllib.request.Request(
        BASE + "/admin/kds/dish-screen/bind",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + token,
            "X-Shop-Id": str(SHOP_ID),
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    if pymysql is None:
        print("pip install pymysql", file=sys.stderr)
        sys.exit(1)

    token = sys.argv[1] if len(sys.argv) > 1 else None
    if token:
        try:
            j = bind_via_api(token)
            print("API:", json.dumps(j, ensure_ascii=False, indent=2))
            if j.get("code") != 0:
                sys.exit(4)
        except urllib.error.HTTPError as e:
            print("API failed:", e.read().decode(), file=sys.stderr)
            sys.exit(3)

    result = bind_via_db()
    print(
        f"DB bind shop={SHOP_ID} screen={SCREEN_TAG}: "
        f"insert={result['inserted']} update={result['updated']} skip={result['skipped']}"
    )
    if result["missing"]:
        print("missing dish_id:", result["missing"])
    print(f"total on screen: {len(result['list'])}")
    for r in result["list"]:
        print(f"  {r['dish_id']:4} {r['name']}")


if __name__ == "__main__":
    main()
