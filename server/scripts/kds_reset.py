#!/usr/bin/env python3
"""
清空 KDS 运行时数据（工单、整单厨显状态、流转批次、抓串记录等），保留档口/绑屏/配置/设备。

不清空：t_kds_station、t_kds_station_category、t_kds_dish_screen、t_kds_shop_config、t_kds_device
不修改：t_order、t_order_detail

示例：
  python server/scripts/kds_reset.py --dry-run
  python server/scripts/kds_reset.py --shop-id 1 --yes
  python server/scripts/kds_reset.py --all-shops --yes

数据库连接（环境变量，任选其一组）：
  KDS_DB_HOST / KDS_DB_USER / KDS_DB_PASSWORD / KDS_DB_NAME
  或 MYSQL_HOST / MYSQL_USER / MYSQL_PASSWORD / MYSQL_DATABASE
默认：127.0.0.1 db_diancan（密码须通过环境变量提供）

清空后如需让未结账订单重新进厨显：POST /admin/kds/ticket/repush（按订单补推）。
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    import pymysql
except ImportError:
    pymysql = None

RUNTIME_TABLES = (
    ("t_kds_flow_batch", "shop_id"),
    ("t_kds_ticket", "shop_id"),
    ("t_kds_order", "shop_id"),
    ("t_kds_skewer_pick", "shop_id"),
)


def db_config() -> dict:
    host = os.environ.get("KDS_DB_HOST") or os.environ.get("MYSQL_HOST") or "127.0.0.1"
    user = os.environ.get("KDS_DB_USER") or os.environ.get("MYSQL_USER") or "db_diancan"
    password = os.environ.get("KDS_DB_PASSWORD") or os.environ.get("MYSQL_PASSWORD")
    database = os.environ.get("KDS_DB_NAME") or os.environ.get("MYSQL_DATABASE") or "db_diancan"
    if not password:
        print(
            "错误：未设置数据库密码。请设置环境变量 KDS_DB_PASSWORD 或 MYSQL_PASSWORD。",
            file=sys.stderr,
        )
        sys.exit(2)
    return {
        "host": host,
        "user": user,
        "password": password,
        "database": database,
        "charset": "utf8mb4",
    }


def connect():
    if pymysql is None:
        print("错误：需要安装 pymysql（pip install pymysql）", file=sys.stderr)
        sys.exit(2)
    return pymysql.connect(**db_config())


def table_exists(cur, table: str) -> bool:
    cur.execute(
        "SELECT COUNT(*) AS c FROM information_schema.tables "
        "WHERE table_schema = DATABASE() AND table_name = %s",
        (table,),
    )
    return int(cur.fetchone()["c"]) > 0


def count_rows(cur, table: str, shop_col: str, shop_id: int | None) -> int:
    if not table_exists(cur, table):
        return -1
    if shop_id is None:
        cur.execute(f"SELECT COUNT(*) AS c FROM `{table}`")
    else:
        cur.execute(f"SELECT COUNT(*) AS c FROM `{table}` WHERE `{shop_col}` = %s", (shop_id,))
    return int(cur.fetchone()["c"])


def delete_rows(cur, table: str, shop_col: str, shop_id: int | None) -> int:
    if not table_exists(cur, table):
        print(f"  [skip] {table} 表不存在，跳过")
        return 0
    if shop_id is None:
        cur.execute(f"DELETE FROM `{table}`")
    else:
        cur.execute(f"DELETE FROM `{table}` WHERE `{shop_col}` = %s", (shop_id,))
    return cur.rowcount


def truncate_all(cur, table: str) -> None:
    if not table_exists(cur, table):
        print(f"  [skip] {table} 表不存在，跳过")
        return
    cur.execute(f"TRUNCATE TABLE `{table}`")


def print_counts(cur, shop_id: int | None, include_sync: bool) -> None:
    scope = "全部门店" if shop_id is None else f"shop_id={shop_id}"
    print(f"=== KDS 运行时数据统计 ({scope}) ===")
    for table, col in RUNTIME_TABLES:
        cnt = count_rows(cur, table, col, shop_id)
        label = "（表不存在）" if cnt < 0 else str(cnt)
        print(f"  {table}: {label}")
    if include_sync:
        cnt = count_rows(cur, "t_kds_sync_dedup", "shop_id", shop_id)
        label = "（表不存在）" if cnt < 0 else str(cnt)
        print(f"  t_kds_sync_dedup: {label}")


def confirm(args) -> bool:
    if args.yes:
        return True
    scope = "全部门店" if args.all_shops else f"shop_id={args.shop_id}"
    print(f"即将清空 KDS 运行时数据（{scope}），配置与设备将保留。")
    ans = input("确认执行？输入 yes 继续: ").strip().lower()
    return ans == "yes"


def main() -> int:
    parser = argparse.ArgumentParser(description="重置 KDS：清空厨显工单等运行时数据")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--shop-id", type=int, default=1, help="仅清空指定门店（默认 1）")
    scope.add_argument("--all-shops", action="store_true", help="清空全部门店运行时数据")
    parser.add_argument("--dry-run", action="store_true", help="仅统计行数，不写库")
    parser.add_argument("--yes", "-y", action="store_true", help="跳过确认")
    parser.add_argument(
        "--skip-sync-dedup",
        action="store_true",
        help="保留 t_kds_sync_dedup（离线同步幂等键）",
    )
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="全门店模式下使用 TRUNCATE（更快，自增 id 归零）；默认 DELETE",
    )
    args = parser.parse_args()

    shop_id: int | None = None if args.all_shops else args.shop_id
    include_sync = not args.skip_sync_dedup

    conn = connect()
    try:
        with conn.cursor(pymysql.cursors.DictCursor) as cur:
            print_counts(cur, shop_id, include_sync)
            if args.dry_run:
                print("（dry-run，未修改数据库）")
                return 0

            if not confirm(args):
                print("已取消")
                return 1

            conn.begin()
            try:
                if shop_id is None and args.truncate:
                    print("执行 TRUNCATE …")
                    for table, _ in RUNTIME_TABLES:
                        truncate_all(cur, table)
                        print(f"  TRUNCATE {table}")
                    if include_sync:
                        truncate_all(cur, "t_kds_sync_dedup")
                        print("  TRUNCATE t_kds_sync_dedup")
                else:
                    print("执行 DELETE …")
                    total = 0
                    for table, col in RUNTIME_TABLES:
                        n = delete_rows(cur, table, col, shop_id)
                        print(f"  DELETE {table}: {n} 行")
                        total += n
                    if include_sync:
                        n = delete_rows(cur, "t_kds_sync_dedup", "shop_id", shop_id)
                        print(f"  DELETE t_kds_sync_dedup: {n} 行")
                        total += n
                    print(f"合计删除 {total} 行")
                conn.commit()
            except Exception:
                conn.rollback()
                raise

            print_counts(cur, shop_id, include_sync)
            print("完成。厨显端请刷新；需要时可 POST /admin/kds/ticket/repush 补推工单。")
            return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
