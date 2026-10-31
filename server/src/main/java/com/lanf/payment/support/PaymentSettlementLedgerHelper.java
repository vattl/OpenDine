package com.lanf.payment.support;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shift;
import com.lanf.entity.Shop;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IShiftService;
import com.lanf.service.IShopService;
import com.lanf.service.PaymentLedgerService;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.receivable.service.ReceivableService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 订单支付不可变台账记录帮助类 (POS-SDC-101 / POS-SDC-102)。
 * 统一处理线上支付（微信小程序/扫码、余额支付等）与收银台账同步、钱箱会话关联及日结自愈。
 */
@Component
public class PaymentSettlementLedgerHelper {

    private static final Logger log = LoggerFactory.getLogger(PaymentSettlementLedgerHelper.class);
    private static final ZoneId SHANGHAI_ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired(required = false)
    private PaymentLedgerService paymentLedgerService;
    @Autowired(required = false)
    private DrawerSessionService drawerSessionService;
    @Autowired(required = false)
    private IShiftService shiftService;
    @Autowired(required = false)
    private IShopService shopService;

    /**
     * 确保订单写入不可变支付台账：
     * 1. 幂等：若该单已有成功的 PAYMENT 记录，直接返回现有记录，不重复插入；
     * 2. 钱箱与班次绑定：自动匹配当前门店处于活动状态（OPEN / CLOSING）的钱箱会话与班次；
     * 3. 渠道拆分与金额校验：对齐订单净应付金额（OrderNetRevenue.netRevenueFen）。
     *
     * @param order 订单实体（transac_status 必须为 success）
     * @param fallbackDrawerSessionId 显式指定的钱箱会话 ID（可选）
     * @param fallbackOperatorId 显式指定的操作人 ID（可选）
     * @return 成功入账的 PaymentLedger 列表
     */
    public List<PaymentLedger> ensureOrderPaymentLedger(
            Order order, Long fallbackDrawerSessionId, Integer fallbackOperatorId) {
        return writeOrderPaymentLedger(order, fallbackDrawerSessionId, fallbackOperatorId, false, null);
    }

    /**
     * 在订单状态落为 success 之前写入权威资金流水。任何查询或写入异常都向上抛出，
     * 由外层支付事务整体回滚，禁止出现“订单已收款但资金流水缺失”。
     */
    public List<PaymentLedger> recordAuthoritativePayment(
            Order order, Long fallbackDrawerSessionId, Integer fallbackOperatorId, String requestId) {
        if (!StringUtils.hasText(requestId)) {
            throw new IllegalArgumentException("权威资金流水幂等号不能为空");
        }
        return writeOrderPaymentLedger(
                order, fallbackDrawerSessionId, fallbackOperatorId, true, requestId.trim());
    }

    private List<PaymentLedger> writeOrderPaymentLedger(
            Order order, Long fallbackDrawerSessionId, Integer fallbackOperatorId,
            boolean strict, String authoritativeRequestId) {
        if (order == null || order.getId() == null || !"success".equalsIgnoreCase(order.getTransac_status())) {
            if (strict) throw new IllegalStateException("订单尚未准备好写入权威资金流水");
            return Collections.emptyList();
        }
        // 挂账完成的是销售/履约状态，不代表已经收款；真实回款只进入应收流水。
        if (ReceivableService.PAYMENT_METHOD_RECEIVABLE.equals(order.getPayment_method())) {
            return Collections.emptyList();
        }
        if (paymentLedgerService == null) {
            if (strict) throw new IllegalStateException("权威资金流水服务不可用，禁止完成结账");
            log.warn("PaymentLedgerService 未启用，跳过台账写入: order_no={}", order.getOrder_no());
            return Collections.emptyList();
        }

        Integer shopId = order.getShop_id();
        String orderNo = order.getOrder_no();
        if (shopId == null || !StringUtils.hasText(orderNo)) {
            if (strict) throw new IllegalStateException("订单缺少门店或订单号，禁止写入权威资金流水");
            return Collections.emptyList();
        }

        // 1. 幂等检查：若已有成功的 PAYMENT 台账，直接返回
        try {
            List<PaymentLedger> existing = paymentLedgerService.listByOrder(shopId, orderNo);
            if (existing != null) {
                List<PaymentLedger> successfulPayments = new ArrayList<>();
                for (PaymentLedger ledger : existing) {
                    if (PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())
                            && PaymentLedger.STATUS_SUCCEEDED.equals(ledger.getStatus())) {
                        successfulPayments.add(ledger);
                    }
                }
                if (!successfulPayments.isEmpty()) {
                    // 严格模式继续进入 PaymentLedgerService，由领域服务逐项核验请求号、
                    // 渠道、金额和三方交易号；非严格自愈模式保持历史兼容。
                    if (!strict) return existing;
                }
            }
        } catch (Exception ex) {
            if (strict) throw new IllegalStateException("核验既有权威资金流水失败，禁止完成结账", ex);
            log.warn("查询已有支付台账异常: order_no={}, err={}", orderNo, ex.getMessage());
        }

        // 2. 匹配活动钱箱与班次
        Long drawerSessionId = fallbackDrawerSessionId;
        Integer operatorId = fallbackOperatorId;
        String terminalId = null;
        Long employeeShiftId = null;

        if (drawerSessionId == null && drawerSessionService != null) {
            try {
                DrawerSession activeSession = drawerSessionService.getActiveSession(shopId, null, null);
                if (activeSession == null) {
                    activeSession = drawerSessionService.getOne(new QueryWrapper<DrawerSession>()
                            .eq("shop_id", shopId)
                            .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING)
                            .orderByDesc("id")
                            .last("LIMIT 1"));
                }
                if (activeSession != null) {
                    drawerSessionId = activeSession.getId();
                    terminalId = activeSession.getTerminal_id();
                    if (operatorId == null) {
                        operatorId = activeSession.getOpened_by();
                    }
                }
            } catch (Exception ex) {
                log.warn("解析活动钱箱异常: shopId={}, orderNo={}, err={}", shopId, orderNo, ex.getMessage());
            }
        }

        if (drawerSessionId != null && shiftService != null) {
            try {
                Shift activeShift = shiftService.getOne(new QueryWrapper<Shift>()
                        .eq("drawer_session_id", drawerSessionId)
                        .isNull("end_time")
                        .orderByDesc("id")
                        .last("LIMIT 1"));
                if (activeShift != null) {
                    employeeShiftId = activeShift.getId();
                    if (operatorId == null) {
                        operatorId = activeShift.getAdmin_id();
                    }
                }
            } catch (Exception ex) {
                log.warn("解析班次异常: drawerSessionId={}, orderNo={}, err={}", drawerSessionId, orderNo, ex.getMessage());
            }
        }

        // 3. 解析各支付渠道实付金额（元转分）
        int cashFen = fen(order.getPay_amount_cash());
        int wechatFen = fen(order.getPay_amount_wechat());
        int alipayFen = fen(order.getPay_amount_alipay());
        int balanceFen = fen(order.getPay_amount_balance());
        int giftFen = fen(order.getPay_amount_gift());

        Map<String, Integer> channelAmountsFen = new LinkedHashMap<>();
        if (cashFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_CASH, cashFen);
        if (wechatFen > 0) {
            channelAmountsFen.put(
                    PaymentChannelCatalog.ledgerChannel(order.getPayment_method(), PaymentLedger.CHANNEL_WECHAT),
                    wechatFen);
        }
        if (alipayFen > 0) {
            channelAmountsFen.put(
                    PaymentChannelCatalog.ledgerChannel(order.getPayment_method(), PaymentLedger.CHANNEL_ALIPAY),
                    alipayFen);
        }
        if (balanceFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, balanceFen);
        if (giftFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_GIFT, giftFen);

        int payableFen = OrderNetRevenue.netRevenueFen(order);
        if (channelAmountsFen.isEmpty() && payableFen == 0) {
            channelAmountsFen.put(PaymentLedger.CHANNEL_OTHER, 0);
        } else if (channelAmountsFen.isEmpty() && payableFen > 0) {
            String code = PaymentChannelCatalog.codeFromPaymentMethod(order.getPayment_method());
            if (PaymentChannelCatalog.OFFLINE_WECHAT_QR.equals(code)) {
                channelAmountsFen.put(PaymentLedger.CHANNEL_WECHAT_QR, payableFen);
            } else if (PaymentChannelCatalog.OFFLINE_ALIPAY_QR.equals(code)) {
                channelAmountsFen.put(PaymentLedger.CHANNEL_ALIPAY_QR, payableFen);
            } else if (PaymentChannelCatalog.ONLINE_WECHAT.equals(code)
                    || (order.getPayment_method() != null && order.getPayment_method().contains("微信"))) {
                channelAmountsFen.put(PaymentLedger.CHANNEL_WECHAT, payableFen);
            } else if (PaymentChannelCatalog.ONLINE_ALIPAY.equals(code)
                    || (order.getPayment_method() != null && order.getPayment_method().contains("支付宝"))) {
                channelAmountsFen.put(PaymentLedger.CHANNEL_ALIPAY, payableFen);
            } else if (PaymentChannelCatalog.ONLINE_BALANCE.equals(code)
                    || (order.getPayment_method() != null && order.getPayment_method().contains("余额"))) {
                channelAmountsFen.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, payableFen);
            } else {
                channelAmountsFen.put(PaymentLedger.CHANNEL_OTHER, payableFen);
            }
        }

        // 单一主渠道对齐净应付金额，避免微小精度误差
        if (channelAmountsFen.size() == 1 && payableFen > 0) {
            String singleChannel = channelAmountsFen.keySet().iterator().next();
            if (!PaymentLedger.CHANNEL_GIFT.equals(singleChannel)) {
                channelAmountsFen.put(singleChannel, payableFen);
            }
        }

        // 4. 解析营业日
        String businessDay = null;
        try {
            Shop shop = shopService != null ? shopService.getById(shopId) : null;
            if (shop != null) {
                Date orderTime = order.getPay_time() != null ? order.getPay_time() : order.getOrder_time();
                if (orderTime != null) {
                    LocalDateTime ldt = orderTime.toInstant().atZone(SHANGHAI_ZONE).toLocalDateTime();
                    businessDay = ShopBusinessWindowResolver.operationalBusinessDay(shop, ldt).toString();
                } else {
                    businessDay = ShopBusinessWindowResolver.operationalBusinessDay(shop).toString();
                }
            }
        } catch (Exception ex) {
            log.warn("解析营业日异常: shopId={}, orderNo={}, err={}", shopId, orderNo, ex.getMessage());
        }
        if (!StringUtils.hasText(businessDay)) {
            businessDay = java.time.LocalDate.now().toString();
        }

        // 5. 写入不可变支付台账
        String requestId = StringUtils.hasText(authoritativeRequestId)
                ? authoritativeRequestId
                : "REQ_" + orderNo + "_" + (order.getPay_time() != null ? order.getPay_time().getTime() : System.currentTimeMillis());
        try {
            List<PaymentLedger> ledgers = paymentLedgerService.recordSettlement(
                    order,
                    operatorId,
                    requestId,
                    terminalId,
                    drawerSessionId,
                    employeeShiftId,
                    businessDay,
                    channelAmountsFen,
                    order.getTransaction_id()
            );
            log.info("成功写入订单支付台账: order_no={}, shop_id={}, channels={}, drawer_session_id={}",
                    orderNo, shopId, channelAmountsFen, drawerSessionId);
            return ledgers;
        } catch (Exception ex) {
            if (strict) throw new IllegalStateException("权威资金流水写入失败，禁止完成结账", ex);
            log.error("写入订单支付台账失败: order_no={}, shop_id={}, channels={}, err={}",
                    orderNo, shopId, channelAmountsFen, ex.getMessage(), ex);
            return Collections.emptyList();
        }
    }

    private static int fen(Double yuan) {
        return yuan != null ? (int) Math.round(yuan * 100d) : 0;
    }
}
