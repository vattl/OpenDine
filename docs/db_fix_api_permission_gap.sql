-- ============================================================
-- 修复：DB 权限表（t_api_permission）缺失的 5 条被拦截接口映射
-- 审计：Controller 全量 449 个接口，被 SysInterceptor 拦截的 311 个中，
--       306 个已在 DB 权限表登记；以下 5 个仅靠内置代码兜底
--       （ApiPermissionMapping.java），权限管理界面不可见、不可维护。
-- 幂等：ON DUPLICATE KEY UPDATE（依赖 method+path_pattern 唯一键）。
-- ============================================================

INSERT INTO t_api_permission (method, path_pattern, permission_code, remark) VALUES
('GET', '/admin/printing/preview', 'printing:view|printing:manage', '打印-模板预览（GET，补齐DB登记）'),
('GET', '/cashier/kds/delivery/business-day/orders', 'cashier:operate', 'KDS出餐-营业日订单列表'),
('GET', '/cashier/kds/delivery/business-day/orders/detail', 'cashier:operate', 'KDS出餐-订单详情'),
('POST', '/pay/offline-collect/temp-qrcode', 'cashier:operate', '离线收款-临时收款码'),
('POST', '/pay/offline-collect/confirm', 'cashier:operate', '离线收款-确认收款')
ON DUPLICATE KEY UPDATE permission_code = VALUES(permission_code), remark = VALUES(remark);

-- 校验：应输出 0 行（执行后所有被拦截接口都在 DB 权限表有登记）
-- SELECT a.path_pattern FROM t_api_permission a
-- WHERE a.path_pattern IN ('/admin/printing/preview','/cashier/kds/delivery/business-day/orders',
--   '/cashier/kds/delivery/business-day/orders/detail','/pay/offline-collect/temp-qrcode','/pay/offline-collect/confirm')
--   AND NOT EXISTS (SELECT 1 FROM t_api_permission b WHERE b.method='GET' AND b.path_pattern='/admin/printing/preview' OR b.path_pattern='/cashier/kds/delivery/business-day/orders');
