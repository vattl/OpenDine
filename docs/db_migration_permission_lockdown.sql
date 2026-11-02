-- ============================================================
-- 危险操作接口权限收紧脚本
-- 将所有高风险/删除/资金类接口的权限码统一改为 admin:manage
-- 执行前请备份 t_api_permission
-- ============================================================

-- -----------------------------------------------------------
-- 一、极高风险：删除系统配置/角色/权限/队列
-- -----------------------------------------------------------

-- 删除角色
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/rbac/roles%';

-- 删除权限
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/rbac/permissions%';

-- 删除接口权限映射
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/rbac/api-permissions%';

-- 删除门店配置覆盖
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/settings/store/override%';

-- 清空打印队列
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern LIKE '/admin/printing/devices/%/clear-queue%';

-- 删除供应商
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/inventory/suppliers%';

-- 删除通知规则
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/notifications/rules%';

-- 删除订单（已有 super_admin 硬编码，双重保险）
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/order/delete%';

-- -----------------------------------------------------------
-- 二、资金相关：退款/反结账/改价/折扣/日结
-- -----------------------------------------------------------

-- 后台退款
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/order/refund';

-- 收银端退款
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/order/refund';

-- 收银端退菜
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/order/refundDish';

-- 反结账
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/order/unCheckout';

-- 日结
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/daily/settle';

-- 改价
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/order/updatePrice';

-- 折扣
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/order/discount';

-- 批量发券
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/coupon/batch-send';

-- -----------------------------------------------------------
-- 三、基础数据删除：菜品/分类/桌台/轮播图/公告/优惠券/BOM
-- -----------------------------------------------------------

-- 删除菜品
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'GET' AND path_pattern = '/admin/dish/delete';

-- 删除分类
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'GET' AND path_pattern = '/admin/category/delete';

-- 删除桌台
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'GET' AND path_pattern = '/admin/table/delete';

-- 删除轮播图
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'DELETE' AND path_pattern LIKE '/admin/order/delete_banners%';

-- 删除门店公告
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'GET' AND path_pattern = '/admin/announcement/delete';

-- 删除订单菜品明细
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/orderDetail/delete_menu';

-- 删除优惠券
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'GET' AND path_pattern = '/admin/coupon/delete';

-- 删除兑换码
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/coupon/redeem-code/delete';

-- 删除物料BOM
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/admin/stock-prep/bom/delete';

-- 清台
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE method = 'POST' AND path_pattern = '/cashier/table/clear';

-- -----------------------------------------------------------
-- 四、验证：查看收紧后的 admin:manage 接口数量
-- -----------------------------------------------------------
-- SELECT method, path_pattern, permission_code
-- FROM t_api_permission
-- WHERE permission_code = 'admin:manage'
-- ORDER BY path_pattern;
