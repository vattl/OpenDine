package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.CashMovement;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;

import java.util.List;
import java.util.Map;

public interface DrawerSessionService extends IService<DrawerSession> {

    /**
     * 开启钱箱会话（开班）
     */
    DrawerSession openSession(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Integer adminId,
            int openingFloatFen,
            String businessDay,
            String requestId
    );

    /**
     * 获取指定终端当前活动钱箱会话（OPEN 或 CLOSING）
     */
    DrawerSession getActiveSession(Integer shopId, String terminalId, String drawerCode);

    /**
     * 计算指定钱箱会话当前的理论应有现金金额(分)
     */
    int calculateExpectedCashFen(Long drawerSessionId);

    /**
     * 获取当前推导的实时现金余额(分)
     */
    int getCurrentCashBalanceFen(Long drawerSessionId);

    /**
     * 记录收银现金销售（在结账事务内由系统自动调用）
     */
    CashMovement recordCashSale(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Order order,
            PaymentLedger ledger,
            int cashFen,
            Integer operatorId
    );

    /**
     * 记录收银现金退款/冲正（在反结账/退款事务内由系统自动调用）
     */
    CashMovement recordCashRefund(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Order order,
            PaymentLedger originalLedger,
            int refundFen,
            Integer operatorId,
            String reason
    );

    /**
     * 记录人工现金动作（加钞 CASH_IN / 支取 CASH_OUT / 投库 CASH_DROP / 弹箱 NO_SALE）
     */
    CashMovement recordManualMovement(
            Integer shopId,
            Long drawerSessionId,
            String movementType,
            int amountFen,
            String reasonCode,
            String remark,
            Integer operatorId,
            Integer approverId,
            String requestId
    );

    /**
     * 关箱交班（盲盘点钞 + 差额审批）
     */
    DrawerSession closeSession(
            Integer shopId,
            Long drawerSessionId,
            Integer closedBy,
            int countedCashFen,
            String varianceReasonCode,
            String varianceNote,
            Integer approvedBy,
            String closeRequestId
    );

    /**
     * 查询钱箱会话的所有现金流水明细
     */
    List<CashMovement> listMovements(Long drawerSessionId);

    /**
     * 生成交班综合对账报告（多渠道实收 + 现金流转明细 + 盘点长短款）
     */
    Map<String, Object> getShiftSummaryReport(Long drawerSessionId);

    Map<String, Object> getWorkbench(Integer shopId, Integer adminId);

    Map<String, Object> listShiftReports(Integer shopId, Long cursor, Integer limit);

    Map<String, Object> listCashEvents(Integer shopId, Long drawerSessionId, Long cursor, Integer limit);
}
