package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatNativeApiClient;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.service.IOrderService;
import com.lanf.util.OrderNetRevenue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Objects;

@Service
public class WechatNativePaymentService {
    private static final Logger log = LoggerFactory.getLogger(WechatNativePaymentService.class);
    private static final long QR_TTL_MILLIS = 5 * 60 * 1000L;
    private static final int CONCURRENT_CREATE_POLL_ATTEMPTS = 15;
    private static final long CONCURRENT_CREATE_POLL_INTERVAL_MILLIS = 100L;
    @Autowired private IOrderService orderService;
    @Autowired private WechatNativePaymentAttemptMapper attemptMapper;
    @Autowired private WechatNativeApiClient apiClient;
    @Autowired private PaymentOnlineGuardService onlineGuardService;
    @Autowired private WechatPaymentSuccessService successService;
    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private WechatMerchantRoutingService merchantRoutingService;
    @Autowired(required = false) private com.lanf.service.IOrderDetailService orderDetailService;

    public R create(Integer shopId, String orderNo, String terminalId) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        R guarded = onlineGuardService.checkCashierWechatPay(shopId);
        if (guarded != null) return guarded;
        Order order = findOrder(shopId, orderNo);
        R stateError = validateOrder(order);
        if (stateError != null) return stateError;
        int amountFen = OrderNetRevenue.netRevenueFen(order);
        if (amountFen <= 0) return R.error("订单应付金额必须大于 0");
        WechatNativePaymentAttemptEntity active = findActive(shopId, orderNo);
        if (reusable(active, amountFen)) return response(active, true);
        if (active != null && "CREATING".equals(active.getStatus())) {
            active = awaitConcurrentCreate(shopId, orderNo, amountFen);
            if (reusable(active, amountFen)) return response(active, true);
            return R.error(40931, "上一笔微信下单结果尚未确认，请先查询支付状态");
        }
        if (active != null && "UNKNOWN".equals(active.getStatus())) {
            return R.error(40931, "上一笔微信下单结果尚未确认，请先查询支付状态");
        }
        if (active != null && "CLOSED".equals(active.getStatus())) {
            // Repair attempts closed before active_key was configured to persist NULL.
            // CLOSED is already a definitive non-payable state, so do not call WeChat close again.
            active.setActive_key(null);
            active.setUpdated_at(new Date());
            attemptMapper.updateById(active);
            active = null;
        }
        if (active != null) {
            try {
                if (!isTerminal(active.getStatus())) {
                    apiClient.close(shopId, active.getMerchant_id(), active.getMerchant_config_id(),
                            active.getMerchant_config_version(), active.getOut_trade_no());
                }
                closeLocal(active, "CLOSED");
            } catch (WechatNativeApiClient.ApiException ex) {
                if (ex.isOrderNonexistentOrClosed()) {
                    log.info("[wx-native] create replacing stale active attempt that was nonexistent on wechat shopId={} orderNo={}",
                            shopId, orderNo);
                    closeLocal(active, "CLOSED");
                } else {
                    return R.error(40931, "旧支付单状态尚未确认，请先查询支付状态");
                }
            } catch (RuntimeException ex) {
                return R.error(40931, "旧支付单状态尚未确认，请先查询支付状态");
            }
        }

        com.lanf.payment.routing.PaymentRoutingContext routingCtx =
                new com.lanf.payment.routing.PaymentRoutingContext(shopId, amountFen / 100d,
                        order.getDineInOrTakeOut(), order.getMerchantId());
        routingCtx.orderTime = order.getOrder_time();
        if (orderDetailService != null && order.getId() != null) {
            List<com.lanf.entity.OrderDetail> details = orderDetailService.list(
                    new QueryWrapper<com.lanf.entity.OrderDetail>().eq("mId", order.getId()));
            if (details != null && !details.isEmpty()) {
                for (com.lanf.entity.OrderDetail d : details) {
                    Long gid = d.getDish_id() != null ? d.getDish_id().longValue() : null;
                    String gname = d.getName();
                    Long cid = null;
                    if (d.getCid() != null) {
                        try { cid = Long.parseLong(d.getCid().trim()); } catch (NumberFormatException ignored) {}
                    }
                    java.math.BigDecimal price = d.getTotal_price() != null ? java.math.BigDecimal.valueOf(d.getTotal_price()) : java.math.BigDecimal.ZERO;
                    Integer qty = 1;
                    if (d.getQuantity() != null) {
                        try { qty = Integer.parseInt(d.getQuantity().trim()); } catch (NumberFormatException ignored) {}
                    }
                    routingCtx.goodsItems.add(new com.lanf.payment.routing.PaymentRoutingContext.RoutingGoodsItem(gid, gname, cid, price, qty));
                }
            }
        }
        String merchantId = merchantRoutingService.route(routingCtx);
        WechatMerchantKeyStore.ResolvedMerchant merchant = merchantKeyStore.resolveForPay(shopId, merchantId, null);
        if (merchant == null || merchant.dbConfigId == null || merchant.dbConfigVersion == null) {
            return R.error(40230, "当前门店未配置可用的微信支付商户");
        }
        order.setMerchant_config_id(merchant.dbConfigId); order.setMerchant_key(merchant.merchantKey);
        order.setMerchant_config_version(merchant.dbConfigVersion); order.setMerchantId(merchantId);
        if (!orderService.updateById(order)) return R.error("保存订单支付商户绑定失败，请重试");
        Date expiresAt = new Date(System.currentTimeMillis() + QR_TTL_MILLIS);
        WechatNativePaymentAttemptEntity attempt = new WechatNativePaymentAttemptEntity();
        attempt.setShop_id(shopId); attempt.setOrder_id(order.getId()); attempt.setOrder_no(orderNo);
        attempt.setOut_trade_no(PaymentOrderNoUtil.buildOutTradeNo(orderNo));
        attempt.setMerchant_id(merchantId); attempt.setAmount_fen(amountFen); attempt.setStatus("CREATING");
        attempt.setMerchant_config_id(merchant.dbConfigId); attempt.setMerchant_key(merchant.merchantKey);
        attempt.setMerchant_config_version(merchant.dbConfigVersion);
        attempt.setActive_key(activeKey(shopId, orderNo)); attempt.setTerminal_id(trim(terminalId));
        attempt.setExpires_at(expiresAt); attempt.setCreated_at(new Date()); attempt.setUpdated_at(new Date());
        try {
            attemptMapper.insert(attempt);
        } catch (DuplicateKeyException conflict) {
            WechatNativePaymentAttemptEntity winner = awaitConcurrentCreate(shopId, orderNo, amountFen);
            if (reusable(winner, amountFen)) return response(winner, true);
            return R.error(40931, "该订单正在创建支付二维码，请稍后查询");
        }
        try {
            WechatNativeApiClient.CreateResult created = apiClient.create(
                    shopId, merchantId, attempt.getMerchant_config_id(), attempt.getMerchant_config_version(),
                    attempt.getOut_trade_no(), amountFen, "门店订单 " + orderNo, expiresAt);
            attempt.setCode_url(created.codeUrl); attempt.setStatus("ACTIVE"); attempt.setTrade_state("NOTPAY");
            attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
            return response(attempt, false);
        } catch (WechatNativeApiClient.ApiException ex) {
            if (ex.isDefinitiveRejection()) {
                attempt.setStatus("CLOSED");
                attempt.setTrade_state("PAYERROR");
                attempt.setActive_key(null);
                attempt.setUpdated_at(new Date());
                attemptMapper.updateById(attempt);
                log.warn("[wx-native] create rejected shopId={} orderNo={} outTradeNo={} httpStatus={} "
                                + "wechatCode={} requestId={}",
                        shopId, orderNo, attempt.getOut_trade_no(), ex.httpStatus, ex.wechatCode, ex.requestId);
                String message = StringUtils.hasText(ex.wechatMessage)
                        ? "微信拒绝下单：" + ex.wechatMessage
                        : "微信拒绝下单，请检查商户配置或订单参数";
                R rejected = R.error(40231, message);
                if (StringUtils.hasText(ex.wechatCode)) rejected.put("wechatCode", ex.wechatCode);
                if (StringUtils.hasText(ex.requestId)) rejected.put("requestId", ex.requestId);
                return rejected;
            }
            attempt.setStatus("UNKNOWN"); attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
            log.error("[wx-native] create uncertain shopId={} orderNo={} outTradeNo={} httpStatus={} "
                            + "wechatCode={} requestId={} cause={}",
                    shopId, orderNo, attempt.getOut_trade_no(), ex.httpStatus, ex.wechatCode, ex.requestId,
                    ex.getCause() == null ? ex.getClass().getSimpleName() : ex.getCause().getClass().getSimpleName());
            return R.error(50331, "微信下单结果暂不确定，请先查询支付状态，勿重复收款");
        } catch (RuntimeException ex) {
            attempt.setStatus("UNKNOWN"); attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
            log.error("[wx-native] create unexpected shopId={} orderNo={} outTradeNo={} cause={}",
                    shopId, orderNo, attempt.getOut_trade_no(), ex.getClass().getSimpleName());
            return R.error(50331, "微信下单结果暂不确定，请先查询支付状态，勿重复收款");
        }
    }

    public R query(Integer shopId, String orderNo) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        Order order = findOrder(shopId, orderNo);
        if (order == null) return R.error("订单不存在或不属于当前门店");
        WechatNativePaymentAttemptEntity attempt = findLatest(shopId, orderNo);
        if (attempt == null) return R.error(40431, "未找到该订单的微信扫码支付记录");
        try {
            WechatNativeApiClient.QueryResult result = apiClient.query(shopId, attempt.getMerchant_id(),
                    attempt.getMerchant_config_id(), attempt.getMerchant_config_version(), attempt.getOut_trade_no());
            attempt.setTrade_state(result.tradeState); attempt.setLast_queried_at(new Date()); attempt.setUpdated_at(new Date());
            if ("SUCCESS".equals(result.tradeState)) {
                WechatPaymentSuccessService.ApplyResult applied = successService.apply(orderNo,
                        attempt.getOut_trade_no(), result.asPaymentResult(attempt.getOut_trade_no()),
                        attempt.getMerchant_id(), attempt.getAmount_fen(), attempt.getShop_id());
                if (!applied.success) return R.error(40932, applied.message);
                attempt.setStatus("SUCCESS"); attempt.setTransaction_id(result.transactionId);
                attempt.setSuccess_time(new Date()); attempt.setActive_key(null);
            } else if ("CLOSED".equals(result.tradeState) || "REVOKED".equals(result.tradeState)
                    || "PAYERROR".equals(result.tradeState)) {
                attempt.setStatus("CLOSED"); attempt.setActive_key(null);
            }
            attemptMapper.updateById(attempt);
            return statusResponse(attempt);
        } catch (WechatNativeApiClient.ApiException ex) {
            if (ex.isOrderNonexistentOrClosed() && ("UNKNOWN".equals(attempt.getStatus()) || "CREATING".equals(attempt.getStatus()))) {
                log.info("[wx-native] query discovered unknown attempt nonexistent on wechat shopId={} orderNo={} outTradeNo={}",
                        shopId, orderNo, attempt.getOut_trade_no());
                closeLocal(attempt, "CLOSED");
                attempt.setTrade_state("NOTPAY");
                return statusResponse(attempt);
            }
            return R.error(50332, "微信查单暂时失败，请稍后重试");
        } catch (RuntimeException ex) {
            return R.error(50332, "微信查单暂时失败，请稍后重试");
        }
    }

    public R close(Integer shopId, String orderNo) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        Order order = findOrder(shopId, orderNo);
        if (order == null) return R.error("订单不存在或不属于当前门店");
        if ("success".equals(order.getTransac_status())) return R.error(40933, "订单已支付，不能关单");
        WechatNativePaymentAttemptEntity attempt = findActive(shopId, orderNo);
        if (attempt == null) return R.ok().put("closed", true).put("idempotent", true);
        if (isTerminal(attempt.getStatus())) {
            closeLocal(attempt, "CLOSED");
            return R.ok().put("closed", true).put("idempotent", true);
        }
        try {
            apiClient.close(shopId, attempt.getMerchant_id(), attempt.getMerchant_config_id(),
                    attempt.getMerchant_config_version(), attempt.getOut_trade_no());
            closeLocal(attempt, "CLOSED");
            return R.ok().put("closed", true).put("outTradeNo", attempt.getOut_trade_no());
        } catch (WechatNativeApiClient.ApiException ex) {
            if (ex.isOrderNonexistentOrClosed()) {
                log.info("[wx-native] close recognized nonexistent or already closed on wechat shopId={} orderNo={} outTradeNo={} code={}",
                        shopId, orderNo, attempt.getOut_trade_no(), ex.wechatCode);
                closeLocal(attempt, "CLOSED");
                return R.ok().put("closed", true).put("outTradeNo", attempt.getOut_trade_no()).put("nonexistentOnWechat", true);
            }
            return R.error(50333, "微信关单失败，请先查单确认支付状态");
        } catch (RuntimeException ex) {
            return R.error(50333, "微信关单失败，请先查单确认支付状态");
        }
    }

    private R validateOrder(Order order) {
        if (order == null) return R.error("订单不存在或不属于当前门店");
        if (StringUtils.hasText(order.getMaster_order_no())) return R.error("该订单为并台从单，请通过主桌统一结账");
        if ("success".equals(order.getTransac_status())) return R.error(40934, "订单已支付");
        if (!"unsettled".equals(order.getTransac_status())) return R.error("订单状态不允许支付");
        return null;
    }
    private R validateInput(Integer shopId, String orderNo) {
        if (shopId == null || shopId <= 0) return R.error(401, "缺少门店上下文");
        if (!StringUtils.hasText(orderNo)) return R.error("orderNo 不能为空");
        return null;
    }
    private Order findOrder(Integer shopId, String orderNo) {
        return orderService.getOne(new QueryWrapper<Order>().eq("shop_id", shopId).eq("order_no", orderNo).last("LIMIT 1"));
    }
    private WechatNativePaymentAttemptEntity findActive(Integer shopId, String orderNo) {
        return attemptMapper.selectOne(new QueryWrapper<WechatNativePaymentAttemptEntity>()
                .eq("active_key", activeKey(shopId, orderNo)).last("LIMIT 1"));
    }
    private WechatNativePaymentAttemptEntity findLatest(Integer shopId, String orderNo) {
        return attemptMapper.selectOne(new QueryWrapper<WechatNativePaymentAttemptEntity>()
                .eq("shop_id", shopId).eq("order_no", orderNo).orderByDesc("id").last("LIMIT 1"));
    }
    private WechatNativePaymentAttemptEntity awaitConcurrentCreate(Integer shopId, String orderNo, int amountFen) {
        WechatNativePaymentAttemptEntity observed = null;
        for (int attempt = 0; attempt < CONCURRENT_CREATE_POLL_ATTEMPTS; attempt++) {
            observed = findActive(shopId, orderNo);
            if (reusable(observed, amountFen)) return observed;
            if (observed != null && !"CREATING".equals(observed.getStatus())
                    && !"ACTIVE".equals(observed.getStatus())) return observed;
            if (attempt + 1 < CONCURRENT_CREATE_POLL_ATTEMPTS && !pauseBeforeRetry()) return observed;
        }
        return observed;
    }
    private boolean pauseBeforeRetry() {
        try {
            Thread.sleep(CONCURRENT_CREATE_POLL_INTERVAL_MILLIS);
            return true;
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
    private boolean reusable(WechatNativePaymentAttemptEntity a, int amountFen) {
        return a != null && "ACTIVE".equals(a.getStatus()) && StringUtils.hasText(a.getCode_url())
                && Objects.equals(a.getAmount_fen(), amountFen) && a.getExpires_at() != null
                && a.getExpires_at().after(new Date());
    }
    private void closeLocal(WechatNativePaymentAttemptEntity a, String state) {
        a.setStatus(state); a.setTrade_state(state); a.setActive_key(null); a.setUpdated_at(new Date());
        attemptMapper.updateById(a);
    }
    private R response(WechatNativePaymentAttemptEntity a, boolean reused) {
        return R.ok().put("paymentId", a.getId()).put("orderNo", a.getOrder_no())
                .put("outTradeNo", a.getOut_trade_no()).put("codeUrl", a.getCode_url())
                .put("amountFen", a.getAmount_fen()).put("expiresAt", a.getExpires_at())
                .put("tradeState", a.getTrade_state()).put("reused", reused);
    }
    private R statusResponse(WechatNativePaymentAttemptEntity a) {
        return R.ok().put("paymentId", a.getId()).put("orderNo", a.getOrder_no())
                .put("outTradeNo", a.getOut_trade_no()).put("amountFen", a.getAmount_fen())
                .put("tradeState", a.getTrade_state()).put("status", a.getStatus())
                .put("transactionId", a.getTransaction_id());
    }
    private static String activeKey(Integer shopId, String orderNo) { return shopId + ":" + orderNo; }
    private static boolean isTerminal(String status) {
        return "CLOSED".equals(status) || "PAYERROR".equals(status) || "REVOKED".equals(status) || "SUCCESS".equals(status);
    }
    private static String trim(String value) { return StringUtils.hasText(value) ? value.trim() : null; }
}
