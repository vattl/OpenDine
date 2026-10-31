package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;

import java.util.List;
import java.util.Map;

/**
 * 不可变支付账本服务 (POS-SDC-101 / POS-SDC-102)
 */
public interface PaymentLedgerService extends IService<PaymentLedger> {

    /**
     * 在结账本地事务中，原子记录不可变分渠道流水，并强制校验资金不变量：
     * Σ channelAmountsFen == orderPayableFen
     */
    List<PaymentLedger> recordSettlement(
            Order order,
            Integer operatorId,
            String requestId,
            String terminalId,
            Long drawerSessionId,
            Long employeeShiftId,
            String businessDay,
            Map<String, Integer> channelAmountsFen,
            String providerTransactionId);

    /**
     * 在反结账事务中，将原订单对应所有成功 PAYMENT 流水进行全额冲正 (写入负向 REVERSAL 流水)
     */
    List<PaymentLedger> recordReversal(
            Order order,
            Integer operatorId,
            String requestId,
            String businessDay,
            String reason);

    /**
     * 记录退款流水 (REFUND，负向金额)
     */
    PaymentLedger recordRefund(
            Order order,
            String channel,
            int refundFen,
            Integer operatorId,
            String requestId,
            String businessDay,
            Long originalLedgerId,
            String providerRefundId);

    List<PaymentLedger> listByOrder(Integer shopId, String orderNo);

    List<PaymentLedger> listByBusinessDay(Integer shopId, String businessDay);
}
