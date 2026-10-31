#!/usr/bin/env python3
"""Read DB history + POST /order/create or /order/addDishes for KDS sim order."""
import json
import sys
import urllib.request
import uuid
from datetime import datetime

try:
    import pymysql
except ImportError:
    pymysql = None

DB = dict(host="127.0.0.1", user="db_diancan", password=__import__("os").environ["DB_PASSWORD"], database="db_diancan", charset="utf8mb4")
BASE = "http://127.0.0.1:8080"
SHOP_ID = 1
# 历史明细检索关键词（烤制/KDS 常用；避免过宽如单独「油」会命中饮品）
HISTORY_NAME_PATTERNS = [
    "%油边%",
    "%油 边%",
    "%吊龙%",
    "%牛肉%",
    "%鸡翅%",
    "%秘制%",
    "%羊肉%",
    "%鸡爪%",
    "%澳椒%",
    "%牛油大串%",
]
HISTORY_DETAIL_LIMIT = 200
RECENT_DINEIN_ORDER_LIMIT = 30
KDS_ORDER_PREFIX_LIMIT = 20
# 除固定菜品外，再从合并历史里补若干行（去重菜名，沿用历史 cid/辣度/数量）
HISTORY_EXTRA_DISH_LINES = 8
# 堂食不可用桌号（与 OrderController 一致：666 为打包专用扫码）
DINE_IN_RESERVED_TABLES = frozenset({"666"})

# 按历史库内 canonical 菜名（先查库再下单，避免误匹配如「牛油大串」）
WANT_BY_DISH_ID = [
    (17, 1, "微辣"),   # 油 边 王
    (18, 3, "不辣"),   # 吊龙牛肉
    (19, 2, "微辣"),   # 羊肉大串
    (20, 4, "微辣"),   # 秘制鸡翅
    (21, 1, "中辣"),   # 销魂鸡爪
]


def print_order_detail_groups(title, rows, id_key="order_id"):
    """按订单聚合打印明细。"""
    print(title)
    if not rows:
        print("  (无记录)")
        return
    by_order = {}
    order_meta = {}
    for row in rows:
        oid = row[id_key]
        if oid not in by_order:
            by_order[oid] = []
            order_meta[oid] = row
        by_order[oid].append(row)
    for oid in sorted(by_order.keys(), reverse=True):
        meta = order_meta[oid]
        head = (
            f"  订单 id={oid} no={meta.get('order_no')} "
            f"桌={meta.get('table_number')} status={meta.get('transac_status')} "
            f"time={meta.get('order_time')}"
        )
        print(head)
        for it in by_order[oid]:
            spicy = it.get("selectedSpicy") or ""
            print(
                f"    - {it.get('name')} x{it.get('quantity')} {it.get('unit') or ''} "
                f"¥{it.get('total_price')} {spicy}"
            )


def merge_history_rows(*row_lists):
    """合并多路历史明细，按 order_id、detail_id 去重，保留较新记录。"""
    seen = set()
    merged = []
    for rows in row_lists:
        for row in rows or []:
            key = (row.get("order_id"), row.get("detail_id"))
            if key in seen:
                continue
            seen.add(key)
            merged.append(row)
    merged.sort(key=lambda r: (r.get("order_id") or 0, r.get("detail_id") or 0), reverse=True)
    return merged


def find_hist_for_name(name, pool):
    """按菜名匹配历史行（精确优先）。"""
    if not name or not pool:
        return None
    target = name.strip()
    for row in pool:
        if (row.get("name") or "").strip() == target:
            return row
    return None


def parse_spicy_from_hist(hist_row, default="微辣"):
    if not hist_row:
        return default
    raw = hist_row.get("selectedSpicy")
    if not raw:
        return default
    if isinstance(raw, str):
        s = raw.strip()
        if s.startswith("{"):
            try:
                obj = json.loads(s)
                if isinstance(obj, dict):
                    return obj.get("辣度") or obj.get("spicy") or default
            except json.JSONDecodeError:
                pass
        return s or default
    return default


def parse_qty_from_hist(hist_row, default=1):
    if not hist_row:
        return default
    try:
        q = float(str(hist_row.get("quantity") or default).strip())
        return max(1, int(round(q)))
    except (TypeError, ValueError):
        return default


def fetch_history_by_dish_names(cur):
    placeholders = " OR ".join(["d.name LIKE %s"] * len(HISTORY_NAME_PATTERNS))
    sql = f"""
        SELECT o.id AS order_id, o.order_no, o.table_number, o.transac_status, o.order_time,
               d.id AS detail_id, d.name, d.quantity, d.unit, d.total_price,
               d.selectedSpicy, d.cid
        FROM t_order_detail d
        JOIN t_order o ON o.id = d.mId
        WHERE o.shop_id = %s AND ({placeholders})
        ORDER BY o.id DESC, d.id DESC
        LIMIT %s
    """
    cur.execute(sql, (SHOP_ID, *HISTORY_NAME_PATTERNS, HISTORY_DETAIL_LIMIT))
    return cur.fetchall()


def fetch_recent_dinein_orders(cur):
    cur.execute(
        """
        SELECT o.id AS order_id, o.order_no, o.table_number, o.transac_status, o.order_time,
               d.id AS detail_id, d.name, d.quantity, d.unit, d.total_price,
               d.selectedSpicy, d.cid
        FROM t_order o
        JOIN t_order_detail d ON d.mId = o.id
        WHERE o.shop_id = %s AND o.dineInOrTakeOut = '堂食'
          AND o.id IN (
              SELECT id FROM (
                  SELECT id FROM t_order
                  WHERE shop_id = %s AND dineInOrTakeOut = '堂食'
                  ORDER BY id DESC
                  LIMIT %s
              ) recent
          )
        ORDER BY o.id DESC, d.id ASC
        """,
        (SHOP_ID, SHOP_ID, RECENT_DINEIN_ORDER_LIMIT),
    )
    return cur.fetchall()


def fetch_kds_prefixed_orders(cur):
    cur.execute(
        """
        SELECT o.id AS order_id, o.order_no, o.table_number, o.transac_status, o.order_time,
               d.id AS detail_id, d.name, d.quantity, d.unit, d.total_price,
               d.selectedSpicy, d.cid
        FROM t_order o
        JOIN t_order_detail d ON d.mId = o.id
        WHERE o.shop_id = %s AND o.order_no LIKE 'KDS%%'
          AND o.id IN (
              SELECT id FROM (
                  SELECT id FROM t_order
                  WHERE shop_id = %s AND order_no LIKE 'KDS%%'
                  ORDER BY id DESC
                  LIMIT %s
              ) recent
          )
        ORDER BY o.id DESC, d.id ASC
        """,
        (SHOP_ID, SHOP_ID, KDS_ORDER_PREFIX_LIMIT),
    )
    return cur.fetchall()


def norm_table(value):
    if value is None:
        return ""
    return str(value).strip()


def is_reserved_dinein_table(value):
    return norm_table(value) in DINE_IN_RESERVED_TABLES


def fetch_open_dinein_orders(cur):
    cur.execute(
        """
        SELECT id, table_number, order_no, order_time
        FROM t_order
        WHERE shop_id = %s AND dineInOrTakeOut = '堂食' AND transac_status = 'unsettled'
        ORDER BY order_time DESC
        """,
        (SHOP_ID,),
    )
    return cur.fetchall()


def pick_free_table(tables, open_orders):
    busy = {norm_table(o.get("table_number")) for o in open_orders}
    for t in tables:
        num = norm_table(t.get("number"))
        if not num or is_reserved_dinein_table(num):
            continue
        if num not in busy:
            return num
    return None


def pick_add_dishes_target(open_orders):
    """无空闲桌时：优先对 KDS 前缀未结账单加菜（跳过打包专用桌）。"""
    candidates = [
        o for o in (open_orders or []) if not is_reserved_dinein_table(o.get("table_number"))
    ]
    if not candidates:
        return None
    for o in candidates:
        ono = (o.get("order_no") or "").strip()
        if ono.upper().startswith("KDS"):
            return o
    return candidates[0]


def http_json(method, path, body=None, headers=None):
    h = {"Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        h.update(headers)
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    if pymysql is None:
        print("pip install pymysql", file=sys.stderr)
        sys.exit(1)

    conn = pymysql.connect(**DB)
    cur = conn.cursor(pymysql.cursors.DictCursor)

    history = fetch_history_by_dish_names(cur)
    print_order_detail_groups(
        f"=== 历史订单明细（烤制关键词，最多 {HISTORY_DETAIL_LIMIT} 条明细）===",
        history,
    )

    recent = fetch_recent_dinein_orders(cur)
    print_order_detail_groups(
        f"\n=== 最近 {RECENT_DINEIN_ORDER_LIMIT} 笔堂食订单明细 ===",
        recent,
    )

    kds_hist = fetch_kds_prefixed_orders(cur)
    print_order_detail_groups(
        f"\n=== 最近 {KDS_ORDER_PREFIX_LIMIT} 笔 KDS 模拟单（order_no 前缀 KDS）===",
        kds_hist,
    )

    history_pool = merge_history_rows(history, recent, kds_hist)
    print(f"\n=== 合并历史池（去重后 {len(history_pool)} 条明细，供下单参考）===")

    print("\n=== 在售菜品（t_dish + 门店价，烤制相关）===")
    dish_like = tuple(HISTORY_NAME_PATTERNS[:8])
    dish_placeholders = " OR ".join(["d.name LIKE %s"] * len(dish_like))
    cur.execute(
        f"""
        SELECT d.id, d.name, d.unitprice AS base_price, d.unit, d.specification, d.onsale,
               ds.unitprice AS shop_price, ds.stock, ds.sold_out,
               c.cid AS category_cid, c.label AS category_label
        FROM t_dish d
        LEFT JOIN t_dish_shop ds ON ds.dish_id = d.id AND ds.shop_id = %s
        LEFT JOIN t_category c ON c.id = d.typeId
        WHERE ({dish_placeholders})
        ORDER BY d.name
        """,
        (SHOP_ID, *dish_like),
    )
    dishes = cur.fetchall()
    for row in dishes:
        print(row)

    # pick best dish per want line from history cid/name/price
    def price_of(d):
        sp = d.get("shop_price")
        return float(sp if sp is not None else d["base_price"] or 0)

    dish_by_id = {d["id"]: d for d in dishes}

    def append_goods_line(d, qty, spicy, hist_row=None, tag="固定"):
        unit_price = price_of(d)
        total = round(unit_price * qty, 2)
        hr = hist_row or find_hist_for_name(d["name"], history_pool)
        selected = json.dumps({"辣度": spicy}, ensure_ascii=False)
        cid = None
        if hr and hr.get("cid"):
            cid = hr["cid"]
        elif d.get("category_cid"):
            cid = d["category_cid"]
        line = {
            "name": d["name"],
            "quantity": str(qty),
            "unit": d["unit"] or "串",
            "unitprice": unit_price,
            "total_price": total,
            "selectedSpicy": selected,
        }
        if cid:
            line["cid"] = cid
        goods.append(line)
        src = f"历史单 id={hr['order_id']}" if hr and hr.get("order_id") else "无历史"
        print(f"\n选用[{tag}]: {line} ({src})")
        return line

    goods = []
    used_names = set()
    for dish_id, qty, spicy in WANT_BY_DISH_ID:
        d = dish_by_id.get(dish_id)
        if not d:
            cur.execute(
                """
                SELECT d.id, d.name, d.unitprice AS base_price, d.unit, d.specification, d.onsale,
                       ds.unitprice AS shop_price, c.cid AS category_cid
                FROM t_dish d
                LEFT JOIN t_dish_shop ds ON ds.dish_id = d.id AND ds.shop_id = %s
                LEFT JOIN t_category c ON c.id = d.typeId
                WHERE d.id = %s
                """,
                (SHOP_ID, dish_id),
            )
            d = cur.fetchone()
            if d:
                dish_by_id[dish_id] = d
        if not d:
            print(f"ERROR: 菜品 id={dish_id} 不存在", file=sys.stderr)
            sys.exit(2)
        hist_row = find_hist_for_name(d["name"], history_pool)
        q = parse_qty_from_hist(hist_row, qty)
        sp = parse_spicy_from_hist(hist_row, spicy)
        append_goods_line(d, q, sp, hist_row, tag="固定")
        used_names.add((d["name"] or "").strip())

    extra_added = 0
    for hist_row in history_pool:
        if extra_added >= HISTORY_EXTRA_DISH_LINES:
            break
        name = (hist_row.get("name") or "").strip()
        if not name or name in used_names:
            continue
        d = next((x for x in dishes if (x.get("name") or "").strip() == name), None)
        if not d:
            cur.execute(
                """
                SELECT d.id, d.name, d.unitprice AS base_price, d.unit, d.specification, d.onsale,
                       ds.unitprice AS shop_price, c.cid AS category_cid
                FROM t_dish d
                LEFT JOIN t_dish_shop ds ON ds.dish_id = d.id AND ds.shop_id = %s
                LEFT JOIN t_category c ON c.id = d.typeId
                WHERE d.name = %s
                LIMIT 1
                """,
                (SHOP_ID, name),
            )
            d = cur.fetchone()
        if not d:
            continue
        q = parse_qty_from_hist(hist_row, 1)
        sp = parse_spicy_from_hist(hist_row, "微辣")
        append_goods_line(d, q, sp, hist_row, tag="历史补行")
        used_names.add(name)
        extra_added += 1
    if extra_added:
        print(f"\n已从历史池追加 {extra_added} 个菜品（上限 {HISTORY_EXTRA_DISH_LINES}）")

    sett = round(sum(g["total_price"] for g in goods), 2)

    print("\n=== 门店桌台 ===")
    cur.execute(
        """
        SELECT t.number, t.status FROM t_table t
        WHERE t.shop_id = %s OR t.shop_id IS NULL
        ORDER BY t.number
        """,
        (SHOP_ID,),
    )
    tables = cur.fetchall()
    print(f"共 {len(tables)} 张桌")

    open_orders = fetch_open_dinein_orders(cur)
    busy_tables = sorted({norm_table(o.get("table_number")) for o in open_orders if norm_table(o.get("table_number"))})
    print("未结账桌号:", busy_tables)
    if open_orders:
        print("未结账单（最近优先）:")
        for o in open_orders[:10]:
            print(f"  - 桌={norm_table(o.get('table_number'))} no={o.get('order_no')}")

    table_no = pick_free_table(tables, open_orders)
    add_target = None
    use_add_dishes = False
    if table_no:
        print(f"模拟开新单桌号: {table_no}")
    else:
        add_target = pick_add_dishes_target(open_orders)
        if not add_target:
            print("ERROR: 无空闲桌且无未结账堂食单可加菜", file=sys.stderr)
            sys.exit(2)
        table_no = norm_table(add_target.get("table_number")) or "8"
        use_add_dishes = True
        print(
            f"无空闲桌，改走加菜: 桌={table_no} order_no={add_target.get('order_no')}"
        )

    cur.execute(
        "SELECT openid FROM t_user WHERE openid IS NOT NULL AND openid <> '' ORDER BY id DESC LIMIT 1"
    )
    u = cur.fetchone()
    openid = (u or {}).get("openid") or "kds-sim-openid-" + uuid.uuid4().hex[:12]

    new_order_no = datetime.now().strftime("KDS%y%m%d%H%M%S") + uuid.uuid4().hex[:6].upper()
    order_no = (add_target or {}).get("order_no") or new_order_no
    payload = {
        "openid": openid,
        "shop_id": SHOP_ID,
        "dineInOrTakeOut": "堂食",
        "number_of_diners": "2",
        "table_number": table_no,
        "order_no": order_no,
        "sett_amount": sett,
        "discount_amount": 0,
        "remark": "KDS模拟下单" if not use_add_dishes else "KDS模拟加菜",
        "goods_list": goods,
    }

    # 历史常点但总部 onsale=0 的菜；模拟下单前临时上架（仅测试）
    for prep_id, label in ((20, "秘制鸡翅"), (21, "销魂鸡爪")):
        d = dish_by_id.get(prep_id)
        if d and d.get("onsale") not in (b"\x01", 1, True):
            print(f"\n[prep] {label}(id={prep_id}) 当前下架，临时 SET onsale=1 以便模拟下单")
            cur.execute("UPDATE t_dish SET onsale=1 WHERE id=%s", (prep_id,))
            conn.commit()

    api_path = "/order/addDishes" if use_add_dishes else "/order/create"
    print(f"\n=== POST {api_path} ===")
    print(json.dumps(payload, ensure_ascii=False, indent=2))

    try:
        resp = http_json("POST", api_path, payload, {"X-Shop-Id": str(SHOP_ID)})
    except Exception as e:
        print("HTTP 失败:", e, file=sys.stderr)
        sys.exit(3)

    print("\n响应:", json.dumps(resp, ensure_ascii=False, indent=2))
    if resp.get("code") != 0 and not use_add_dishes:
        existing_no = (resp.get("order_no") or "").strip()
        msg = resp.get("msg") or ""
        if existing_no and "未结账" in msg:
            print(f"\n开新单被拒，改走加菜: {existing_no}")
            payload["order_no"] = existing_no
            payload["remark"] = "KDS模拟加菜(自动回退)"
            try:
                resp = http_json(
                    "POST", "/order/addDishes", payload, {"X-Shop-Id": str(SHOP_ID)}
                )
            except Exception as e:
                print("加菜 HTTP 失败:", e, file=sys.stderr)
                sys.exit(3)
            print("\n加菜响应:", json.dumps(resp, ensure_ascii=False, indent=2))
    if resp.get("code") != 0:
        sys.exit(4)

    oid = resp.get("id")
    ono = resp.get("order_no") or order_no
    print(f"\n成功 order_id={oid} order_no={ono}")

    cur.execute(
        "SELECT COUNT(*) AS c FROM t_kds_ticket WHERE order_id = %s", (oid,)
    )
    tc = cur.fetchone()
    print("t_kds_ticket 数量:", tc)

    cur.execute(
        """
        SELECT id, screen_tag, item_status, detail_id FROM t_kds_ticket WHERE order_id = %s
        """,
        (oid,),
    )
    for t in cur.fetchall():
        print(" ticket:", t)

    conn.close()


if __name__ == "__main__":
    main()
