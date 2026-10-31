package com.lanf.service;

import com.lanf.entity.ChannelStatementBatch;
import com.lanf.entity.ReconciliationCase;

import java.util.List;
import java.util.Map;

/**
 * 渠道对账与三层差异处理服务接口 (POS-SDC-401 & POS-SDC-402)
 */
public interface IReconciliationService {

    /**
     * 导入渠道对账单（支持微信/支付宝 CSV 及标准 JSON）
     * 具备 SHA-256 防重、格式校验、错误行报告与明细持久化
     */
    ChannelStatementBatch importStatement(Integer shopId, Integer adminId, String channel, String fileName, String contentText);

    /**
     * 获取指定营业日的三层对账全景概览
     * Layer 1: 订单 vs 内部支付台账
     * Layer 2: 内部支付台账 vs 渠道对账单（若未导入账单强制标记 UNIMPORTED，绝不可显示已对平）
     * Layer 3: 渠道账单 vs 手续费与结算净额
     */
    Map<String, Object> getReconciliationOverview(Integer shopId, String statDate);

    /**
     * 查询渠道账单导入批次列表
     */
    List<ChannelStatementBatch> getBatches(Integer shopId, String statDate, String channel);

    /**
     * 查询对账差异处理单列表
     */
    List<ReconciliationCase> getCases(Integer shopId, String statDate, String status, String discrepancyType);

    /**
     * 处理/解决对账差异单
     */
    ReconciliationCase resolveCase(Integer shopId, Integer adminId, Long caseId, String status, String resolutionNote, String responsiblePerson);
}
