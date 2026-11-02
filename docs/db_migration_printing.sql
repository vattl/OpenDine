-- ============================================================
-- 打印模块（协调文档 §2：打印设备列表/保存、打印规则、打印测试、打印任务记录）
-- 幂等：可重复执行。已有数据零影响。
-- 依赖说明：
--   * t_printing_device 被 docs/db_migration_system_settings.sql 的概览统计查询引用，
--     本脚本创建后该统计才真正生效（查询侧已做缺表容错）。
-- ============================================================

-- 1) 打印设备
CREATE TABLE IF NOT EXISTS `t_printing_device` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '设备 ID',
  `shop_id` int NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `name` varchar(128) NOT NULL COMMENT '设备名称',
  `transport` varchar(20) NOT NULL COMMENT '连接方式：LAN/USB/BLUETOOTH/CLOUD',
  `brand` varchar(64) DEFAULT NULL COMMENT '品牌/型号，如 飞鹅/佳博/芯烨',
  `connection_json` text COMMENT '连接参数 JSON（IP/端口/序列号sn/密钥key等；接口读取时密钥与序列号脱敏）',
  `status` varchar(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '运行状态：ONLINE/OFFLINE/UNKNOWN',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本，从 1 起',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_printing_device_shop` (`shop_id`,`transport`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='打印设备';

-- 2) 打印规则（场景 → 设备/模板/份数）
CREATE TABLE IF NOT EXISTS `t_printing_rule` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '规则 ID',
  `shop_id` int NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `scenario` varchar(32) NOT NULL COMMENT '打印场景：order/kitchen/refund/shift…',
  `device_id` bigint DEFAULT NULL COMMENT 't_printing_device.id，为空则暂不指派设备',
  `template_code` varchar(64) DEFAULT NULL COMMENT '打印模板编码，映射品牌适配器',
  `copies` int NOT NULL DEFAULT 1 COMMENT '打印份数，1-9',
  `enabled` tinyint NOT NULL DEFAULT 1 COMMENT '是否启用：1 启用 / 0 停用',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本（门店规则集整体版本 = 本店各行最大值）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_printing_rule_shop_scenario` (`shop_id`,`scenario`),
  KEY `idx_printing_rule_shop_device` (`shop_id`,`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='打印规则';

-- 3) 打印任务记录（含测试单；不含任何「远程重启打印服务」能力）
CREATE TABLE IF NOT EXISTS `t_printing_job` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '任务 ID',
  `shop_id` int NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `device_id` bigint DEFAULT NULL COMMENT 't_printing_device.id',
  `job_type` varchar(32) NOT NULL COMMENT '标准场景码：kitchen/full_order/pre_checkout/checkout/expedite/takeout/shift/refund/label/test 或合法自定义码；历史 order/serve 保留兼容',
  `status` varchar(20) NOT NULL DEFAULT 'PENDING_DEVICE' COMMENT '状态：PENDING_DEVICE/SENT/PRINTED/FAILED/CANCELED',
  `payload_text` longtext COMMENT '打印内容文本',
  `error` varchar(500) DEFAULT NULL COMMENT '失败原因',
  `retry_count` int NOT NULL DEFAULT 0 COMMENT '已重试次数（仅记录，本模块不提供远程重试入口）',
  `executor` varchar(10) NOT NULL COMMENT '执行方：CLOUD（服务端走飞鹅云）/DEVICE（端侧本地执行）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_printing_job_shop_time` (`shop_id`,`created_at`),
  KEY `idx_printing_job_shop_device_status` (`shop_id`,`device_id`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='打印任务记录';

-- 4) 权限码注册
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('printing:view',   '打印查看', 'printing', '打印设备列表、打印规则、打印任务记录查看', 62),
('printing:manage', '打印管理', 'printing', '打印设备新建/更新、打印测试、打印规则保存', 63);

-- 5) 接口-权限映射（DbApiPermissionMapping 启动/重载后生效）
--    注意：t_api_permission 在部分安装上存在 uk_path_pattern(path_pattern) 唯一键；
--    与 db_migration_system_settings.sql 一致，采用「同路径按 method 分行」写法，
--    在带唯一键的安装上 PUT/POST 行会被 INSERT IGNORE 静默忽略（降级为 view|manage 双码），
--    不影响幂等，也不比参考模块更弱。
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',  '/admin/printing/devices',        'printing:view|printing:manage'),
('POST', '/admin/printing/devices',        'printing:manage'),
('PUT',  '/admin/printing/devices/*',      'printing:manage'),
('GET',  '/admin/printing/rules',          'printing:view|printing:manage'),
('PUT',  '/admin/printing/rules',          'printing:manage'),
('POST', '/admin/printing/devices/*/test', 'printing:manage'),
('GET',  '/admin/printing/jobs',           'printing:view|printing:manage');

-- 6) 授权：超级管理员全量
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('printing:view','printing:manage')
WHERE r.role_code = 'super_admin';

-- 6.1) 门店角色：仅授予查看（管理操作保留给超级管理员）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code = 'printing:view'
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
