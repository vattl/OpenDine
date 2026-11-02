-- ============================================================
-- 接口权限细粒度化（基于线上 t_api_permission / t_permission 导出，2026-09-07）
-- 幂等；执行后需重载权限映射（POST /admin/rbac/api-permissions/reload）或重启。
-- ============================================================

-- 2. 接口映射细粒度化（按 path_pattern 定位，线上 method 均为 *）
UPDATE t_api_permission SET permission_code = 'access:view' WHERE id = 994;
UPDATE t_api_permission SET permission_code = 'access:manage' WHERE id = 1100;
UPDATE t_api_permission SET permission_code = 'access:manage' WHERE id = 998;
UPDATE t_api_permission SET permission_code = 'statistics:view:dashboard' WHERE id = 4;
UPDATE t_api_permission SET permission_code = 'statistics:view:dashboard' WHERE id = 5;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 6;
UPDATE t_api_permission SET permission_code = 'statistics:view:dishRanking' WHERE id = 7;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 8;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 9;
UPDATE t_api_permission SET permission_code = 'announcement:view' WHERE id = 12;
UPDATE t_api_permission SET permission_code = 'announcement:view' WHERE id = 13;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 23;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 24;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:view' WHERE id = 25;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:manage' WHERE id = 26;
UPDATE t_api_permission SET permission_code = 'payment:config:read' WHERE id = 27;
UPDATE t_api_permission SET permission_code = 'coupon:manage' WHERE id = 1133;
UPDATE t_api_permission SET permission_code = 'statistics:view:sales' WHERE id = 29;
UPDATE t_api_permission SET permission_code = 'statistics:view:profit' WHERE id = 30;
UPDATE t_api_permission SET permission_code = 'statistics:view:sales' WHERE id = 31;
UPDATE t_api_permission SET permission_code = 'daily:settle' WHERE id = 32;
UPDATE t_api_permission SET permission_code = 'statistics:view:sales' WHERE id = 33;
UPDATE t_api_permission SET permission_code = 'inventory:manage' WHERE id = 1160;
UPDATE t_api_permission SET permission_code = 'inventory:manage' WHERE id = 1161;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 364;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 43;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 46;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 49;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 363;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 51;
UPDATE t_api_permission SET permission_code = 'kds:view' WHERE id = 54;
UPDATE t_api_permission SET permission_code = 'log:view' WHERE id = 57;
UPDATE t_api_permission SET permission_code = 'log:archive' WHERE id = 967;
UPDATE t_api_permission SET permission_code = 'log:archive' WHERE id = 1187;
UPDATE t_api_permission SET permission_code = 'log:export' WHERE id = 969;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:manage' WHERE id = 984;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:manage' WHERE id = 1190;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:manage' WHERE id = 986;
UPDATE t_api_permission SET permission_code = 'marketing:firstorder:view' WHERE id = 987;
UPDATE t_api_permission SET permission_code = 'notifications:view' WHERE id = 974;
UPDATE t_api_permission SET permission_code = 'notifications:view' WHERE id = 971;
UPDATE t_api_permission SET permission_code = 'notifications:manage' WHERE id = 1208;
UPDATE t_api_permission SET permission_code = 'notifications:manage' WHERE id = 1209;
UPDATE t_api_permission SET permission_code = 'order:operate:discount' WHERE id = 81;
UPDATE t_api_permission SET permission_code = 'statistics:view:sales' WHERE id = 86;
UPDATE t_api_permission SET permission_code = 'statistics:view:dashboard' WHERE id = 1228;
UPDATE t_api_permission SET permission_code = 'statistics:view:dashboard' WHERE id = 1229;
UPDATE t_api_permission SET permission_code = 'order:view:list' WHERE id = 91;
UPDATE t_api_permission SET permission_code = 'payment:view' WHERE id = 95;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 1235;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 1236;
UPDATE t_api_permission SET permission_code = 'payment:config:read' WHERE id = 96;
UPDATE t_api_permission SET permission_code = 'payment:config:read' WHERE id = 98;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 99;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 1238;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 1239;
UPDATE t_api_permission SET permission_code = 'payment:view' WHERE id = 100;
UPDATE t_api_permission SET permission_code = 'payment:config:read' WHERE id = 101;
UPDATE t_api_permission SET permission_code = 'payment:config:write' WHERE id = 102;
UPDATE t_api_permission SET permission_code = 'payment:view' WHERE id = 103;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 977;
UPDATE t_api_permission SET permission_code = 'printing:view' WHERE id = 1247;
UPDATE t_api_permission SET permission_code = 'printing:view' WHERE id = 1249;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 1250;
UPDATE t_api_permission SET permission_code = 'printing:view' WHERE id = 981;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 1252;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 979;
UPDATE t_api_permission SET permission_code = 'printing:view' WHERE id = 1084;
UPDATE t_api_permission SET permission_code = 'printing:view' WHERE id = 1259;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 1257;
UPDATE t_api_permission SET permission_code = 'printing:manage' WHERE id = 1258;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 111;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 112;
UPDATE t_api_permission SET permission_code = 'statistics:view:dashboard' WHERE id = 113;
UPDATE t_api_permission SET permission_code = 'statistics:view:dishRanking' WHERE id = 114;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 115;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 116;
UPDATE t_api_permission SET permission_code = 'statistics:view:recharge' WHERE id = 117;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 1279;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 1280;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 1281;
UPDATE t_api_permission SET permission_code = 'statistics:view:profit' WHERE id = 118;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 119;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 120;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 1285;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 1286;
UPDATE t_api_permission SET permission_code = 'statistics:view:inventory' WHERE id = 122;
UPDATE t_api_permission SET permission_code = 'statistics:view:report' WHERE id = 123;
UPDATE t_api_permission SET permission_code = 'report:export' WHERE id = 1289;
UPDATE t_api_permission SET permission_code = 'settings:view|settings:manage' WHERE id = 960;
UPDATE t_api_permission SET permission_code = 'settings:view|settings:manage' WHERE id = 961;
UPDATE t_api_permission SET permission_code = 'shop:manage' WHERE id = 124;
UPDATE t_api_permission SET permission_code = 'shop:manage' WHERE id = 125;
UPDATE t_api_permission SET permission_code = 'shop:manage' WHERE id = 126;
UPDATE t_api_permission SET permission_code = 'table:operate' WHERE id = 139;
UPDATE t_api_permission SET permission_code = 'table:operate' WHERE id = 140;
UPDATE t_api_permission SET permission_code = 'table:operate:clear' WHERE id = 173;
UPDATE t_api_permission SET permission_code = 'table:operate:merge' WHERE id = 174;
UPDATE t_api_permission SET permission_code = 'table:operate:open' WHERE id = 175;
UPDATE t_api_permission SET permission_code = 'table:operate:transfer' WHERE id = 177;
UPDATE t_api_permission SET permission_code = 'order:operate:discount' WHERE id = 161;
UPDATE t_api_permission SET permission_code = 'order:operate:unCheckout' WHERE id = 167;
UPDATE t_api_permission SET permission_code = 'order:operate:changePrice' WHERE id = 168;
UPDATE t_api_permission SET permission_code = 'order:view:detail' WHERE id = 183;
UPDATE t_api_permission SET permission_code = 'order:view:list' WHERE id = 165;
UPDATE t_api_permission SET permission_code = 'order:view:list' WHERE id = 166;
UPDATE t_api_permission SET permission_code = 'order:view:detail' WHERE id = 1340;

-- 2b. 第二批细化（菜品销量统计/支付方式/收银订单详情/KDS通道）
UPDATE t_api_permission SET permission_code = 'order:config:paymentMethod' WHERE id = 759;
UPDATE t_api_permission SET permission_code = 'statistics:view:dishRanking' WHERE id = 87;
UPDATE t_api_permission SET permission_code = 'statistics:view:dishRanking' WHERE id = 88;
UPDATE t_api_permission SET permission_code = 'order:config:paymentMethod' WHERE id = 93;
UPDATE t_api_permission SET permission_code = 'order:config:paymentMethod' WHERE id = 94;
UPDATE t_api_permission SET permission_code = 'order:view:detail' WHERE id = 553;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 554;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 555;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 556;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 557;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 558;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 559;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 1354;
UPDATE t_api_permission SET permission_code = 'kds:operate' WHERE id = 1355;
-- 3. 补充线上缺失的映射（INSERT，撞唯一键则跳过）

-- 4. cashier 角色补授细粒度报表权限（收银首页今日订单/待结账金额/营业额）
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'cashier' AND p.permission_code IN ('statistics:view:dashboard','statistics:view:sales')
  AND NOT EXISTS (SELECT 1 FROM t_role_permission trp WHERE trp.role_id = r.id AND trp.permission_id = p.id);

-- ============================================================
-- 校验：
--   SELECT permission_code, COUNT(*) FROM t_api_permission GROUP BY permission_code ORDER BY COUNT(*) DESC;
-- ============================================================

-- 5. 清理已移除接口 /order/changeWxzf 的权限映射（代码已删除 wxzf 功能）
DELETE FROM t_api_permission WHERE path_pattern LIKE '%changeWxzf%';
