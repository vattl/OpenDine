-- ============================================================
-- 敏感操作接口权限映射回退（当前登录人只需基础码 cashier:operate）
-- 背景：
--   db_fix_permission_granularity.sql(2026-09-07) / db_migration_api_permission_full.sql
--   把 4 个收银敏感接口的【入口】权限码改成了授权员工的敏感码
--   （order:operate:changePrice / discount / refund）。
--   后果：SysInterceptor 在控制器二次授权【之前】要求当前登录收银员
--   自己持有敏感码，收银员角色天然无此码 → 即使店长/超管已现场授权
--   （approvalToken / authorization 密码）也在入口被 403，二次授权被架空。
-- 契约依据：docs/API.md §4 —— cashier:operate + 现场授权员工敏感码；
--           docs/changes/POS-sensitive-operation-authorization-20261005.md
-- 幂等：可重复执行；执行后需 POST /admin/rbac/api-permissions/reload 或重启
--       （DbApiPermissionMapping 为内存缓存）。
-- ============================================================

UPDATE t_api_permission SET permission_code = 'cashier:operate'
WHERE path_pattern IN ('/cashier/order/updatePrice','/cashier/order/discount',
                       '/cashier/order/refund','/cashier/order/refundDish')
  AND permission_code IN ('order:operate:changePrice','order:operate:discount','order:operate:refund');

-- ------------------------------------------------------------
-- 校验（执行后应满足：入口码全部为 cashier:operate，即以下两个查询均返回 0 行）
-- ------------------------------------------------------------
-- 1) 敏感接口入口映射残留敏感码（应空）
-- SELECT path_pattern, permission_code FROM t_api_permission
--  WHERE path_pattern IN ('/cashier/order/updatePrice','/cashier/order/discount',
--                         '/cashier/order/refund','/cashier/order/refundDish')
--    AND permission_code IN ('order:operate:changePrice','order:operate:discount','order:operate:refund');
--
-- 2) 敏感接口入口映射非基础码（应空，即全部为 cashier:operate）
-- SELECT path_pattern, permission_code FROM t_api_permission
--  WHERE path_pattern IN ('/cashier/order/updatePrice','/cashier/order/discount',
--                         '/cashier/order/refund','/cashier/order/refundDish')
--    AND permission_code != 'cashier:operate';
