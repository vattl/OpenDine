package com.lanf.service;

import java.util.Map;

/**
 * 历史账本回填与双写影子切读服务接口 (POS-SDC-501 & POS-SDC-502)
 */
public interface ILedgerMigrationService {

    String READ_SOURCE_PAYMENT_LEDGER = "PAYMENT_LEDGER";
    String READ_SOURCE_LEGACY_ORDER = "LEGACY_ORDER";
    String CONFIG_KEY_READ_SOURCE = "finance.ledger.read_source";

    /**
     * 执行历史订单流水回填（支持干跑演练与正式落账）
     */
    Map<String, Object> executeBackfill(Integer shopId, Integer adminId, String statDate, boolean dryRun);

    /**
     * 对指定营业日执行双写影子验证（旧订单口径 vs 新账本口径逐笔及聚合对比）
     */
    Map<String, Object> shadowVerify(Integer shopId, String statDate);

    /**
     * 获取当前门店的切读状态、回填统计及影子对齐摘要
     */
    Map<String, Object> getCutoverStatus(Integer shopId);

    /**
     * 切换数据读源（LEGACY_ORDER 或 PAYMENT_LEDGER），记录系统配置及审计
     */
    Map<String, Object> cutoverReadSource(Integer shopId, Integer adminId, String targetSource);

    /**
     * 获取当前门店生效的数据读源
     */
    String getReadSource(Integer shopId);
}
