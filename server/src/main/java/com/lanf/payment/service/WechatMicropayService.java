package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatMicropayApiClient;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.entity.WechatMicropayAttemptEntity;
import com.lanf.payment.mapper.WechatMicropayAttemptMapper;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.service.IOrderService;
import com.lanf.util.OrderNetRevenue;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/** 收银员扫描顾客付款码的 MICROPAY 生命周期；付款码只在 pay 调用栈内存在。 */
@Service
public class WechatMicropayService {
    private static final long MIN_REVERSE_AGE_MILLIS = 15_000L;
    @Autowired private IOrderService orderService;
    @Autowired private WechatMicropayAttemptMapper attemptMapper;
    @Autowired private WechatMicropayApiClient apiClient;
    @Autowired private PaymentOnlineGuardService onlineGuardService;
    @Autowired private WechatPaymentSuccessService successService;
    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private WechatMerchantRoutingService merchantRoutingService;
    @Autowired(required = false) private com.lanf.service.IOrderDetailService orderDetailService;

    public R pay(Integer shopId, String orderNo, String authCode, String terminalId, String clientIp) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        if (!validAuthCode(authCode)) return R.error(40031, "微信付款码格式无效，请顾客刷新付款码后重试");
        if (StringUtils.hasText(terminalId) && terminalId.trim().length() > 64) return R.error(40032, "terminalId 不能超过64字符");
        R guarded = onlineGuardService.checkCashierWechatMicropay(shopId);
        if (guarded != null) return guarded;
        Order order = findOrder(shopId, orderNo);
        R stateError = validateOrder(order);
        if (stateError != null) return stateError;
        int amountFen = OrderNetRevenue.netRevenueFen(order);
        if (amountFen <= 0) return R.error("订单应付金额必须大于 0");
        WechatMicropayAttemptEntity active = findActive(shopId, orderNo);
        if (active != null) return R.error(40941, "该订单已有待确认付款码交易，请先查询或撤销");

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
        WechatMicropayAttemptEntity attempt = new WechatMicropayAttemptEntity();
        attempt.setShop_id(shopId); attempt.setOrder_id(order.getId()); attempt.setOrder_no(orderNo);
        attempt.setOut_trade_no(PaymentOrderNoUtil.buildOutTradeNo(orderNo));
        attempt.setMerchant_id(merchantId); attempt.setAmount_fen(amountFen); attempt.setStatus("CREATING");
        attempt.setMerchant_config_id(merchant.dbConfigId); attempt.setMerchant_key(merchant.merchantKey);
        attempt.setMerchant_config_version(merchant.dbConfigVersion);
        attempt.setActive_key(activeKey(shopId, orderNo)); attempt.setTerminal_id(trim(terminalId));
        attempt.setClient_ip(normalizeIp(clientIp)); attempt.setCreated_at(new Date()); attempt.setUpdated_at(new Date());
        try {
            attemptMapper.insert(attempt);
        } catch (DuplicateKeyException e) {
            return R.error(40941, "该订单正在处理付款码交易，请先查询支付状态");
        }

        try {
            WechatMicropayApiClient.Result result = apiClient.pay(shopId, merchantId,
                    attempt.getMerchant_config_id(), attempt.getMerchant_config_version(), attempt.getOut_trade_no(),
                    amountFen, authCode, attempt.getTerminal_id(), attempt.getClient_ip());
            return applyResult(attempt, result);
        } catch (RuntimeException e) {
            attempt.setStatus("UNKNOWN"); attempt.setTrade_state("UNKNOWN"); attempt.setUpdated_at(new Date());
            attemptMapper.updateById(attempt);
            return R.error(50341, "微信扣款结果暂不确定，请查询状态，勿重复扫码或改用其他渠道");
        }
    }

    public R query(Integer shopId, String orderNo) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        if (findOrder(shopId, orderNo) == null) return R.error("订单不存在或不属于当前门店");
        WechatMicropayAttemptEntity attempt = findLatest(shopId, orderNo);
        if (attempt == null) return R.error(40441, "未找到该订单的微信付款码支付记录");
        if (terminal(attempt.getStatus())) return response(attempt);
        try {
            WechatMicropayApiClient.Result result = apiClient.query(shopId, attempt.getMerchant_id(),
                    attempt.getMerchant_config_id(), attempt.getMerchant_config_version(), attempt.getOut_trade_no());
            attempt.setLast_queried_at(new Date());
            return applyResult(attempt, result);
        } catch (RuntimeException e) {
            return R.error(50342, "微信查单暂时失败，请稍后重试");
        }
    }

    public R reverse(Integer shopId, String orderNo) {
        R invalid = validateInput(shopId, orderNo);
        if (invalid != null) return invalid;
        Order order = findOrder(shopId, orderNo);
        if (order == null) return R.error("订单不存在或不属于当前门店");
        if ("success".equals(order.getTransac_status())) return R.error(40943, "订单已支付，不能撤销");
        WechatMicropayAttemptEntity attempt = findActive(shopId, orderNo);
        if (attempt == null) return R.ok().put("reversed", true).put("idempotent", true);
        if (attempt.getCreated_at() == null || System.currentTimeMillis() - attempt.getCreated_at().getTime() < MIN_REVERSE_AGE_MILLIS) {
            return R.error(40944, "交易创建未满15秒，请先等待并查询支付状态");
        }
        try {
            WechatMicropayApiClient.Result queried = apiClient.query(shopId, attempt.getMerchant_id(),
                    attempt.getMerchant_config_id(), attempt.getMerchant_config_version(), attempt.getOut_trade_no());
            if (queried.success()) return applyResult(attempt, queried);
            WechatMicropayApiClient.Result reversed = apiClient.reverse(shopId, attempt.getMerchant_id(),
                    attempt.getMerchant_config_id(), attempt.getMerchant_config_version(), attempt.getOut_trade_no());
            if (!"SUCCESS".equals(reversed.resultCode)) return R.error(50343, "微信撤销尚未确认，请继续查询");
            attempt.setStatus("REVERSED"); attempt.setTrade_state("REVERSED"); attempt.setResult_code(reversed.resultCode);
            attempt.setErr_code(reversed.errCode); attempt.setReversed_at(new Date()); attempt.setActive_key(null);
            attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
            return R.ok().put("reversed", true).put("outTradeNo", attempt.getOut_trade_no());
        } catch (RuntimeException e) {
            return R.error(50343, "微信撤销或前置查单暂不确定，请继续查询，勿重复收款");
        }
    }

    private R applyResult(WechatMicropayAttemptEntity attempt, WechatMicropayApiClient.Result result) {
        attempt.setResult_code(result.resultCode); attempt.setErr_code(result.errCode);
        attempt.setTrade_state(StringUtils.hasText(result.tradeState) ? result.tradeState : result.errCode);
        attempt.setUpdated_at(new Date());
        if (result.success()) {
            WechatPaymentSuccessService.ApplyResult applied = successService.apply(attempt.getOrder_no(),
                    attempt.getOut_trade_no(), result.asPaymentResult(attempt.getOut_trade_no()),
                    attempt.getMerchant_id(), attempt.getAmount_fen(), attempt.getShop_id());
            if (!applied.success) {
                attempt.setStatus("UNKNOWN"); attemptMapper.updateById(attempt);
                return R.error(40942, applied.message);
            }
            attempt.setStatus("SUCCESS"); attempt.setTrade_state("SUCCESS");
            attempt.setTransaction_id(result.transactionId); attempt.setSuccess_time(new Date()); attempt.setActive_key(null);
        } else if (result.userPaying()) {
            attempt.setStatus("USERPAYING"); attempt.setTrade_state("USERPAYING");
        } else if (result.unknown()) {
            attempt.setStatus("UNKNOWN"); attempt.setTrade_state("UNKNOWN");
        } else {
            attempt.setStatus("FAILED"); attempt.setActive_key(null);
        }
        attemptMapper.updateById(attempt);
        if ("FAILED".equals(attempt.getStatus())) {
            return R.error(40241, failureMessage(result.errCode));
        }
        return response(attempt);
    }

    private R response(WechatMicropayAttemptEntity attempt) {
        return R.ok().put("paymentId", attempt.getId()).put("orderNo", attempt.getOrder_no())
                .put("outTradeNo", attempt.getOut_trade_no()).put("amountFen", attempt.getAmount_fen())
                .put("tradeState", attempt.getTrade_state()).put("status", attempt.getStatus())
                .put("transactionId", attempt.getTransaction_id());
    }

    private Order findOrder(Integer shopId, String orderNo) {
        return orderService.getOne(new QueryWrapper<Order>().eq("shop_id", shopId).eq("order_no", orderNo).last("LIMIT 1"));
    }
    private WechatMicropayAttemptEntity findActive(Integer shopId, String orderNo) {
        return attemptMapper.selectOne(new QueryWrapper<WechatMicropayAttemptEntity>()
                .eq("active_key", activeKey(shopId, orderNo)).last("LIMIT 1"));
    }
    private WechatMicropayAttemptEntity findLatest(Integer shopId, String orderNo) {
        return attemptMapper.selectOne(new QueryWrapper<WechatMicropayAttemptEntity>()
                .eq("shop_id", shopId).eq("order_no", orderNo).orderByDesc("id").last("LIMIT 1"));
    }
    private R validateOrder(Order order) {
        if (order == null) return R.error("订单不存在或不属于当前门店");
        if (StringUtils.hasText(order.getMaster_order_no())) return R.error("该订单为并台从单，请通过主桌统一结账");
        if ("success".equals(order.getTransac_status())) return R.error(40945, "订单已支付");
        if (!"unsettled".equals(order.getTransac_status())) return R.error("订单状态不允许支付");
        return null;
    }
    private R validateInput(Integer shopId, String orderNo) {
        if (shopId == null || shopId <= 0) return R.error(401, "缺少门店上下文");
        if (!StringUtils.hasText(orderNo)) return R.error("orderNo 不能为空");
        if (orderNo.trim().length() > 64) return R.error("orderNo 不能超过64字符");
        return null;
    }
    private static boolean validAuthCode(String value) { return value != null && value.matches("1[0-5]\\d{16}"); }
    private static boolean terminal(String status) { return "SUCCESS".equals(status) || "FAILED".equals(status) || "REVERSED".equals(status); }
    private static String activeKey(Integer shopId, String orderNo) { return shopId + ":" + orderNo; }
    private static String trim(String value) { return StringUtils.hasText(value) ? value.trim() : null; }
    private static String normalizeIp(String value) { return StringUtils.hasText(value) && value.length() <= 45 ? value.trim() : "127.0.0.1"; }
    private static String failureMessage(String errCode) {
        if ("AUTHCODEEXPIRE".equals(errCode)) return "付款码已过期，请顾客刷新后重试";
        if ("NOTENOUGH".equals(errCode)) return "顾客余额不足，请更换支付方式";
        if ("AUTH_CODE_ERROR".equals(errCode) || "AUTH_CODE_INVALID".equals(errCode)) return "付款码无效，请顾客刷新后重试";
        return "微信付款失败，请顾客确认后重试";
    }
}
