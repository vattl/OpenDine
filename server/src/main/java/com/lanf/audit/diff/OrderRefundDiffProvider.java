package com.lanf.audit.diff;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.service.IOrderService;
import com.lanf.util.OrderPayChannelAmounts;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 退款/退菜金额类操作的前后状态快照：refund_amount、实付金额与各支付渠道合计。
 * targetId 为订单号（order_no）。查库失败返回 null（不阻断审计记录）。
 */
@Component
public class OrderRefundDiffProvider implements DiffProvider {

    @Autowired
    private IOrderService orderService;

    @Override
    public Map<String, Object> captureBefore(String targetId) {
        return capture(targetId);
    }

    @Override
    public Map<String, Object> captureAfter(String targetId) {
        return capture(targetId);
    }

    private Map<String, Object> capture(String orderNo) {
        if (orderNo == null || orderNo.trim().isEmpty()) {
            return null;
        }
        try {
            Order order = orderService.getOne(
                    new QueryWrapper<Order>().eq("order_no", orderNo.trim()).last("LIMIT 1"));
            if (order == null) {
                return null;
            }
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("orderNo", order.getOrder_no());
            m.put("transacStatus", order.getTransac_status());
            m.put("refundAmount", order.getRefund_amount());
            m.put("settAmount", order.getSett_amount());
            m.put("channelTotalFen", OrderPayChannelAmounts.totalPayChannelAmountFen(order));
            return m;
        } catch (Exception e) {
            return null;
        }
    }
}
