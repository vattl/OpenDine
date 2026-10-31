-- ============================================================
-- 报表导出任务 + 日志查询/归档/导出 模块
-- （协调文档 §2：报表导出任务 / 日志查询 / 归档日志查询 / 日志导出；§4：ARCHIVE_QUERY_PENDING；§5：保留策略）
-- 幂等：可重复执行。已有数据零影响。
--
-- 数据保留策略（写入代码与查询语义，此处为口径说明）：
--   * 在线日志查询（GET /admin/logs）：仅返回近 30 天（t_operation_log.created_at >= now-30d），
--     请求时间窗越出 30 天边界时直接返回空页并附 hint。
--   * 归档日志查询（POST /admin/logs/archive-search / 日志导出）：时间窗放宽至 365 天，
--     仅扫描 created_at 落在 [now-365d, now-30d]（导出为 [now-365d, now]）的数据。
--   * 1 年销毁：超过 365 天的数据视为已按存储策略销毁，归档查询对 >365 天的数据不做返回
--     （查询侧硬边界，实现于 AdminLogService 的窗口裁剪；本库不物理删除历史数据）。
-- ============================================================

-- 1) 导出/归档任务表（报表导出、日志导出、归档检索共用一张任务表，以 job_type 区分）
CREATE TABLE IF NOT EXISTS `t_report_export_job` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '任务ID',
  `shop_id` int NOT NULL COMMENT '门店ID t_shop.id（隔离维度）',
  `job_type` varchar(32) NOT NULL COMMENT '任务类型：REPORT_EXPORT/LOG_EXPORT/ARCHIVE_SEARCH',
  `report_type` varchar(64) DEFAULT NULL COMMENT '报表类型：daily/weekly/monthly；日志类任务为 log',
  `filters_json` text COMMENT '筛选条件 JSON（报表 filters / 日志查询条件 + purpose）',
  `format` varchar(16) NOT NULL DEFAULT 'csv' COMMENT '导出格式：csv/xlsx（当前实现仅 csv）',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT '状态：PENDING/RUNNING/DONE/FAILED',
  `file_name` varchar(255) DEFAULT NULL COMMENT '生成文件名（服务端 ./data/exports 目录下）',
  `download_token` varchar(64) DEFAULT NULL COMMENT '32 位随机下载令牌（完成时生成）',
  `token_expires_at` datetime DEFAULT NULL COMMENT '下载令牌过期时间（生成后 15 分钟）',
  `result_summary_json` text COMMENT '结果摘要 JSON（归档查询存命中数/窗口/提示）',
  `error` varchar(512) DEFAULT NULL COMMENT '失败原因或过期提示（如 download link expired）',
  `created_by` int DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_shop_created` (`shop_id`,`created_at`),
  KEY `idx_shop_type_status` (`shop_id`,`job_type`,`status`),
  KEY `idx_token` (`download_token`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='报表/日志导出与归档检索任务';

-- 2) 权限码注册（权限码分配表：报表→report:view/report:export；日志→log:view/log:archive/log:export）
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('report:view',   '报表查看',   'report', '报表查询与导出任务列表/下载查看', 70),
('report:export', '报表导出',   'report', '创建报表导出任务（仅超级管理员）', 71),
('log:view',      '日志查看',   'log',    '近 30 天在线操作日志查询', 72),
('log:archive',   '日志归档检索', 'log',  '30 天至 1 年归档日志异步检索', 73),
('log:export',    '日志导出',   'log',    '日志导出 CSV（仅超级管理员，需 purpose）', 74);

-- 3) 接口-权限映射（DbApiPermissionMapping 启动加载后生效；写接口只给专用码，GET 可双码）
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('POST', '/admin/reports/exports',            'report:export'),
('GET',  '/admin/reports/exports',            'report:view|report:export'),
('GET',  '/admin/reports/exports/*/download', 'report:view|report:export'),
('GET',  '/admin/logs',                       'log:view'),
('POST', '/admin/logs/archive-search',        'log:archive'),
('GET',  '/admin/logs/archive-search/*',      'log:view|log:archive'),
('POST', '/admin/logs/exports',               'log:export');

-- 4) 授权：超级管理员全量（含仅超管的 report:export / log:export）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN
  ('report:view','report:export','log:view','log:archive','log:export')
WHERE r.role_code = 'super_admin';

-- 5) 授权：门店角色授查看与归档检索；
--    report:export 与 log:export 只授 super_admin（见第 4 节，门店角色刻意不含）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r
JOIN t_permission p ON p.permission_code IN ('report:view','log:view','log:archive')
WHERE r.role_code IN ('shop_manager','shop_admin','store_manager');
