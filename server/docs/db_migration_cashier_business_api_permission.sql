-- ============================================================
-- 收银端营业状态接口权限登记
-- 说明：营业状态变更由运营端 /order/ChangeBusiness 迁移至收银端
--       POST /cashier/shop/business（收银员日常开门/打烊）。
--       force=1 强制跳过（未开班/未交班/未日结）仍由核心逻辑内部校验 admin:manage。
-- 幂等：ON DUPLICATE KEY UPDATE，可重复执行。
-- ============================================================
INSERT INTO t_api_permission (method, path_pattern, permission_code, remark)
VALUES ('POST', '/cashier/shop/business', 'cashier:operate', '收银-营业状态（开门/打烊）')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code), remark = VALUES(remark);
