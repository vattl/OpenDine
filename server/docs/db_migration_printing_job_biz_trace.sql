-- ============================================================
-- t_printing_job 增加业务溯源字段（biz_type / biz_id）
-- 目的：KDS 划菜打印经统一调度中心出票后，可凭业务键反查打印记录
--       （detail_id → 设备 / 内容 / 状态 / 补打次数），闭环审计链路。
-- 幂等：守护式加列，可重复执行。
-- 关联改动：PrintingJob.java / PrintContext.ofServe /
--          PrintDispatcherServiceImpl.executeAndRecordJob /
--          PrintingService.jobSummary
-- ============================================================

DROP PROCEDURE IF EXISTS `p_printing_job_add_biz_cols`;
DELIMITER $$
CREATE PROCEDURE `p_printing_job_add_biz_cols`()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_printing_job' AND COLUMN_NAME = 'biz_type') THEN
    ALTER TABLE `t_printing_job`
      ADD COLUMN `biz_type` varchar(20) DEFAULT NULL COMMENT '业务类型：kds_serve（KDS 划菜）等',
      ADD COLUMN `biz_id`   bigint     DEFAULT NULL COMMENT '业务主键：如 t_order_detail.id',
      ADD KEY `idx_printing_job_biz` (`biz_type`, `biz_id`);
  END IF;
END$$
DELIMITER ;
CALL `p_printing_job_add_biz_cols`();
DROP PROCEDURE IF EXISTS `p_printing_job_add_biz_cols`;
