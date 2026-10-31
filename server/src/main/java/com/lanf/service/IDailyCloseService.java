package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.DailyAdjustment;
import com.lanf.entity.DailyCloseSnapshot;

import java.util.Map;

/**
 * 营业日关账与商业 Z 报表核心服务接口 (POS-SDC-301 ~ POS-SDC-304)
 */
public interface IDailyCloseService extends IService<DailyCloseSnapshot> {

    /**
     * 日结预检：检查阻断项 (open orders, open drawer sessions, pending payments, unapproved variances)
     * 返回结构化 blockers, warnings, preview, precheck_token
     */
    default Map<String, Object> precheck(Integer shopId, String statDate) {
        return precheck(shopId, null, statDate);
    }

    Map<String, Object> precheck(Integer shopId, Integer adminId, String statDate);
    Map<String, Object> precheck(Integer shopId, Integer adminId, String statDate, Integer staleMinutesThreshold);

    /**
     * 日结页面全量上下文聚合：在单一原子时间窗口下获取营业日权威时序、销售汇总、支付渠道明细、预检阻断项及快照状态
     */
    default Map<String, Object> getDailyContext(Integer shopId, String statDate) {
        return getDailyContext(shopId, null, statDate, 30);
    }

    Map<String, Object> getDailyContext(Integer shopId, Integer adminId, String statDate, Integer staleMinutesThreshold);

    /**
     * 一键作废营业日内超过指定时长的未支付打包单/外卖单
     *
     * @param shopId 门店 ID
     * @param adminId 操作人 ID
     * @param statDate 营业日（可选）
     * @param minutesThreshold 超时分钟阈值（默认 30 分钟）
     * @return 包含 voided_count, voided_amount, voided_order_nos 的操作结果
     */
    Map<String, Object> voidStalePackTakeoutOrders(Integer shopId, Integer adminId, String statDate, Integer minutesThreshold);

    /**
     * 执行原子日结关账，生成不可变日结快照并同步 t_daily_stat
     */
    default Map<String, Object> settle(
            Integer shopId,
            Integer adminId,
            String statDate,
            String precheckToken,
            String password,
            boolean force
    ) {
        return settle(shopId, adminId, statDate, precheckToken, password, force, null);
    }

    Map<String, Object> settle(Integer shopId, Integer adminId, String statDate, String precheckToken,
                               String password, boolean force, String idempotencyKey);

    /**
     * 查询指定营业日的商用 Z 报表 (已日结读取不可变快照与调整，未日结提供实时 X 报表预览)
     */
    Map<String, Object> generateZReport(Integer shopId, String statDate);

    Map<String, Object> listZReports(Integer shopId, String dateFrom, String dateTo, Long cursor, Integer limit);

    /**
     * 记录日结后调整（跨日退款或补录）
     */
    DailyAdjustment recordAdjustment(
            Integer shopId,
            Integer adminId,
            Long snapshotId,
            String adjustmentType,
            int amountFen,
            Long orderId,
            Long paymentLedgerId,
            String reason,
            Integer approvedBy
    );

    /**
     * 查询日结后调整列表及调整后净销售额
     */
    Map<String, Object> getAdjustments(Integer shopId, String statDate);

    /**
     * 重开日结（需经理二级认证与原因，记录完整审计）
     */
    Map<String, Object> reopen(
            Integer shopId,
            Integer adminId,
            String statDate,
            String password,
            String reason
    );
}
