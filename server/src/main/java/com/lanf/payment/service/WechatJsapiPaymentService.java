package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.channel.wechat.WechatNativeApiClient;
import com.lanf.payment.entity.WechatJsapiPaymentAttemptEntity;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.mapper.WechatJsapiPaymentAttemptMapper;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.service.IOrderService;
import com.lanf.util.UserWalletSplitUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.interceptor.TransactionAspectSupport;
import org.springframework.util.StringUtils;

import java.util.Date;
import java.util.Map;
import java.util.Objects;

/** JSAPI 支付尝试的唯一生命周期所有者。 */
@Service
public class WechatJsapiPaymentService {
    private static final Logger log = LoggerFactory.getLogger(WechatJsapiPaymentService.class);
    private static final long PREPAY_TTL_MILLIS = 2 * 60 * 1000L;

    @Autowired private IOrderService orderService;
    @Autowired private WechatJsapiPaymentAttemptMapper attemptMapper;
    @Autowired(required = false) private WechatNativePaymentAttemptMapper nativeAttemptMapper;
    @Autowired private WechatNativeApiClient apiClient;
    @Autowired private PaymentSettlementService settlementService;
    @Autowired private WechatMerchantKeyStore merchantKeyStore;
    @Autowired private WechatPaymentSuccessService successService;

    @Transactional(rollbackFor = Exception.class)
    public R create(String orderNo, String openid, Long couponId) {
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo).last("LIMIT 1 FOR UPDATE"));
        if (order == null) return R.error("订单不存在，无法支付");
        if ("success".equals(order.getTransac_status())) return R.error(40934, "订单已支付");
        if (!"unsettled".equals(order.getTransac_status())) return R.error("订单状态异常，无法支付");
        if (StringUtils.hasText(order.getOpenid()) && !order.getOpenid().trim().equals(openid)) {
            return R.error(403, "支付用户与订单绑定用户不一致");
        }
        if (StringUtils.hasText(order.getMaster_order_no())) {
            return R.error("该订单为并台从单，不支持单独结账，请通过主桌统一结账");
        }
        long slaveCount = orderService.count(new QueryWrapper<Order>()
                .eq(order.getShop_id() != null, "shop_id", order.getShop_id())
                .eq("master_order_no", orderNo).eq("transac_status", "unsettled"));
        if (slaveCount > 0) return R.error("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账");

        R settled = settlementService.settle(order, couponId, openid, true);
        if (!ok(settled)) return settled;
        int amountFen = UserWalletSplitUtil.yuanToFen(((Number) settled.get("paidYuan")).doubleValue());
        String merchantId = String.valueOf(settled.get("merchantId"));
        if (amountFen <= 0) return rollback(R.error("折后实付金额异常，无法支付"));

        WechatJsapiPaymentAttemptEntity active = findActive(order.getShop_id(), orderNo);
        if (active != null) {
            R converged = convergeActive(active, amountFen, openid, merchantId);
            if (converged != null) {
                return Integer.valueOf(50331).equals(converged.get("code")) ? rollback(converged) : converged;
            }
        }

        WechatMerchantKeyStore.ResolvedMerchant merchant = merchantKeyStore.resolveForPay(
                order.getShop_id(), merchantId, null);
        if (merchant == null || merchant.dbConfigId == null || merchant.dbConfigVersion == null) {
            return rollback(R.error(40230, "当前门店未配置可用的微信支付商户"));
        }
        order.setMerchantId(merchantId);
        order.setMerchant_config_id(merchant.dbConfigId);
        order.setMerchant_key(merchant.merchantKey);
        order.setMerchant_config_version(merchant.dbConfigVersion);
        if (!orderService.updateById(order)) return rollback(R.error("保存订单支付商户绑定失败，请重试"));

        Date now = new Date();
        Date expiresAt = new Date(now.getTime() + PREPAY_TTL_MILLIS);
        WechatJsapiPaymentAttemptEntity attempt = new WechatJsapiPaymentAttemptEntity();
        attempt.setShop_id(order.getShop_id());
        attempt.setOrder_id(order.getId());
        attempt.setOrder_no(orderNo);
        attempt.setOut_trade_no(PaymentOrderNoUtil.buildOutTradeNo(orderNo));
        attempt.setMerchant_id(merchantId);
        attempt.setMerchant_config_id(merchant.dbConfigId);
        attempt.setMerchant_key(merchant.merchantKey);
        attempt.setMerchant_config_version(merchant.dbConfigVersion);
        attempt.setAmount_fen(amountFen);
        attempt.setPayer_openid(openid);
        attempt.setStatus("CREATING");
        attempt.setActive_key(activeKey(order.getShop_id(), orderNo));
        attempt.setExpires_at(expiresAt);
        attempt.setCreated_at(now);
        attempt.setUpdated_at(now);
        try {
            attemptMapper.insert(attempt);
        } catch (DuplicateKeyException conflict) {
            return rollback(R.error(40931, "该订单正在创建微信支付，请稍后重试"));
        }

        try {
            WechatNativeApiClient.JsapiCreateResult created = apiClient.createJsapi(
                    order.getShop_id(), merchantId, merchant.dbConfigId, merchant.dbConfigVersion,
                    attempt.getOut_trade_no(), amountFen, openid, "老肥油边王", expiresAt);
            attempt.setPrepay_id(created.prepayId);
            attempt.setStatus("ACTIVE");
            attempt.setTrade_state("NOTPAY");
            attempt.setUpdated_at(new Date());
            attemptMapper.updateById(attempt);
            return response(attempt, created.payParams, false);
        } catch (WechatNativeApiClient.ApiException ex) {
            if (ex.isDefinitiveRejection()) {
                release(attempt, "CLOSED", "PAYERROR");
                return R.error(40231, StringUtils.hasText(ex.wechatMessage)
                        ? "微信拒绝下单：" + ex.wechatMessage : "微信拒绝下单，请检查商户配置或订单参数");
            }
            attempt.setStatus("UNKNOWN");
            attempt.setUpdated_at(new Date());
            attemptMapper.updateById(attempt);
            log.error("[wx-jsapi] create uncertain shopId={} orderNo={} outTradeNo={} requestId={}",
                    order.getShop_id(), orderNo, attempt.getOut_trade_no(), ex.requestId);
            return R.error(50331, "微信下单结果暂不确定，请稍后重试，勿重复支付");
        }
    }

    /** 必须在金额变更事务内调用；先锁订单，再关闭仍可支付的旧 JSAPI 及 Native 付款码单。 */
    @Transactional(rollbackFor = Exception.class)
    public Order prepareForAmountMutation(Order suppliedOrder) {
        if (suppliedOrder == null || suppliedOrder.getId() == null) throw new IllegalArgumentException("订单不存在");
        Order locked = orderService.getOne(new QueryWrapper<Order>()
                .eq("id", suppliedOrder.getId()).last("LIMIT 1 FOR UPDATE"));
        if (locked == null) throw new IllegalArgumentException("订单不存在");
        // 锁后重验，覆盖“顾客已拉起支付并在退菜获得锁前完成付款”的竞态。
        // 即使成功回调已释放 active_key，也绝不能继续修改已支付订单。
        if ("success".equals(locked.getTransac_status())) {
            throw new IllegalStateException("订单已被微信支付，不能直接改金额，请走支付后退款流程");
        }
        if (!"unsettled".equals(locked.getTransac_status())) {
            throw new IllegalStateException("订单状态已变化，不能修改订单金额");
        }
        convergeActiveJsapi(locked);
        convergeActiveNative(locked);
        return locked;
    }

    private void convergeActiveJsapi(Order locked) {
        WechatJsapiPaymentAttemptEntity active = findActive(locked.getShop_id(), locked.getOrder_no());
        if (active == null) return;
        WechatNativeApiClient.QueryResult query;
        try {
            query = apiClient.query(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
        } catch (WechatNativeApiClient.ApiException ex) {
            if (orderNotExist(ex)) {
                release(active, "CLOSED", "NOT_FOUND");
                return;
            }
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            attemptMapper.updateById(active);
            throw new IllegalStateException("微信支付状态暂不确定，不能修改订单金额，请稍后重试");
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            attemptMapper.updateById(active);
            throw new IllegalStateException("微信支付状态暂不确定，不能修改订单金额，请稍后重试");
        }
        active.setTrade_state(query.tradeState);
        active.setLast_queried_at(new Date());
        if ("SUCCESS".equals(query.tradeState)) {
            throw new IllegalStateException("订单已被微信支付，不能直接改金额，请走支付后退款流程");
        }
        if (terminal(query.tradeState)) {
            release(active, "CLOSED", query.tradeState);
            return;
        }
        if (!"NOTPAY".equals(query.tradeState)) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            attemptMapper.updateById(active);
            throw new IllegalStateException("微信支付状态暂不确定，不能修改订单金额，请稍后重试");
        }
        try {
            apiClient.close(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
            release(active, "CLOSED", "CLOSED");
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            attemptMapper.updateById(active);
            throw new IllegalStateException("旧微信支付单未能安全关闭，不能修改订单金额，请稍后重试");
        }
    }

    private void convergeActiveNative(Order locked) {
        if (nativeAttemptMapper == null) return;
        String activeKey = activeKey(locked.getShop_id(), locked.getOrder_no());
        WechatNativePaymentAttemptEntity active = nativeAttemptMapper.selectOne(
                new QueryWrapper<WechatNativePaymentAttemptEntity>()
                        .eq("active_key", activeKey).last("LIMIT 1"));
        if (active == null) return;
        WechatNativeApiClient.QueryResult query;
        try {
            query = apiClient.query(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
        } catch (WechatNativeApiClient.ApiException ex) {
            if (orderNotExist(ex)) {
                releaseNative(active, "CLOSED", "NOT_FOUND");
                return;
            }
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            nativeAttemptMapper.updateById(active);
            throw new IllegalStateException("微信Native支付状态暂不确定，不能修改订单金额，请稍后重试");
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            nativeAttemptMapper.updateById(active);
            throw new IllegalStateException("微信Native支付状态暂不确定，不能修改订单金额，请稍后重试");
        }
        active.setTrade_state(query.tradeState);
        active.setLast_queried_at(new Date());
        if ("SUCCESS".equals(query.tradeState)) {
            throw new IllegalStateException("订单已被微信支付，不能直接改金额，请走支付后退款流程");
        }
        if (terminal(query.tradeState)) {
            releaseNative(active, "CLOSED", query.tradeState);
            return;
        }
        if (!"NOTPAY".equals(query.tradeState)) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            nativeAttemptMapper.updateById(active);
            throw new IllegalStateException("微信Native支付状态暂不确定，不能修改订单金额，请稍后重试");
        }
        try {
            apiClient.close(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
            releaseNative(active, "CLOSED", "CLOSED");
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN");
            active.setUpdated_at(new Date());
            nativeAttemptMapper.updateById(active);
            throw new IllegalStateException("旧微信Native支付单未能安全关闭，不能修改订单金额，请稍后重试");
        }
    }

    private void releaseNative(WechatNativePaymentAttemptEntity attempt, String status, String tradeState) {
        attempt.setStatus(status);
        attempt.setTrade_state(tradeState);
        attempt.setActive_key(null);
        attempt.setUpdated_at(new Date());
        nativeAttemptMapper.updateById(attempt);
    }

    public WechatJsapiPaymentAttemptEntity findByOutTradeNo(String outTradeNo) {
        if (!StringUtils.hasText(outTradeNo)) return null;
        return attemptMapper.selectOne(new QueryWrapper<WechatJsapiPaymentAttemptEntity>()
                .eq("out_trade_no", outTradeNo).last("LIMIT 1"));
    }

    @Transactional(rollbackFor = Exception.class)
    public void markClosedByOutTradeNo(String outTradeNo, String tradeState) {
        WechatJsapiPaymentAttemptEntity attempt = findByOutTradeNo(outTradeNo);
        if (attempt != null && !"SUCCESS".equals(attempt.getStatus())) {
            release(attempt, "CLOSED", StringUtils.hasText(tradeState) ? tradeState : "CLOSED");
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public void markCallbackResult(WechatJsapiPaymentAttemptEntity attempt, Map<String, Object> payment,
                                   WechatPaymentSuccessService.ApplyResult applied) {
        if (attempt == null) return;
        attempt.setTrade_state("SUCCESS");
        attempt.setTransaction_id(text(payment.get("transaction_id")));
        attempt.setSuccess_time(new Date());
        attempt.setStatus(applied.success ? "SUCCESS" : "CONFLICT");
        // 外部已扣款但本地校验冲突时保留活动占用，禁止再创建第二笔支付。
        if (applied.success) attempt.setActive_key(null);
        attempt.setUpdated_at(new Date());
        attemptMapper.updateById(attempt);
    }

    private R convergeActive(WechatJsapiPaymentAttemptEntity active, int amountFen,
                             String openid, String merchantId) {
        if (reusable(active, amountFen, openid, merchantId)) {
            try {
                return response(active, apiClient.buildJsapiPayParams(active.getShop_id(), active.getMerchant_id(),
                        active.getMerchant_config_id(), active.getMerchant_config_version(), active.getPrepay_id()), true);
            } catch (RuntimeException ex) {
                return R.error(50331, "微信支付参数生成失败，请稍后重试");
            }
        }
        WechatNativeApiClient.QueryResult query;
        try {
            query = apiClient.query(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
        } catch (WechatNativeApiClient.ApiException ex) {
            if (orderNotExist(ex)) {
                release(active, "CLOSED", "NOT_FOUND");
                return null;
            }
            active.setStatus("UNKNOWN"); active.setUpdated_at(new Date()); attemptMapper.updateById(active);
            return R.error(50331, "上一笔微信支付状态暂不确定，请稍后重试，勿重复支付");
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN"); active.setUpdated_at(new Date()); attemptMapper.updateById(active);
            return R.error(50331, "上一笔微信支付状态暂不确定，请稍后重试，勿重复支付");
        }
        active.setTrade_state(query.tradeState); active.setLast_queried_at(new Date());
        if ("SUCCESS".equals(query.tradeState)) {
            WechatPaymentSuccessService.ApplyResult result = applySuccess(active, query);
            return result.success ? R.error(40934, "订单已支付") : R.error(40932, result.message);
        }
        if (terminal(query.tradeState)) {
            release(active, "CLOSED", query.tradeState);
            return null;
        }
        if (!"NOTPAY".equals(query.tradeState)) {
            active.setStatus("UNKNOWN"); active.setUpdated_at(new Date()); attemptMapper.updateById(active);
            return R.error(50331, "上一笔微信支付状态暂不确定，请稍后重试，勿重复支付");
        }
        try {
            apiClient.close(active.getShop_id(), active.getMerchant_id(), active.getMerchant_config_id(),
                    active.getMerchant_config_version(), active.getOut_trade_no());
            release(active, "CLOSED", "CLOSED");
            return null;
        } catch (RuntimeException ex) {
            active.setStatus("UNKNOWN"); active.setUpdated_at(new Date()); attemptMapper.updateById(active);
            return R.error(50331, "旧微信支付单未能安全关闭，请稍后重试，勿重复支付");
        }
    }

    private WechatPaymentSuccessService.ApplyResult applySuccess(WechatJsapiPaymentAttemptEntity attempt,
                                                                  WechatNativeApiClient.QueryResult query) {
        if (!"JSAPI".equals(query.tradeType)) {
            attempt.setStatus("CONFLICT"); attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
            return WechatPaymentSuccessService.ApplyResult.error("TRADE_TYPE_MISMATCH", "交易类型不匹配");
        }
        if (!StringUtils.hasText(query.payerOpenid)
                || !Objects.equals(attempt.getPayer_openid(), query.payerOpenid)) {
            attempt.setStatus("CONFLICT"); attempt.setUpdated_at(new Date());
            attemptMapper.updateById(attempt);
            return WechatPaymentSuccessService.ApplyResult.error("PAYER_MISMATCH", "支付用户不匹配");
        }
        WechatPaymentSuccessService.ApplyResult result = successService.apply(
                attempt.getOrder_no(), attempt.getOut_trade_no(), query.asPaymentResult(attempt.getOut_trade_no()),
                attempt.getMerchant_id(), attempt.getAmount_fen(), attempt.getShop_id());
        markCallbackResult(attempt, query.asPaymentResult(attempt.getOut_trade_no()), result);
        return result;
    }

    private WechatJsapiPaymentAttemptEntity findActive(Integer shopId, String orderNo) {
        return attemptMapper.selectOne(new QueryWrapper<WechatJsapiPaymentAttemptEntity>()
                .eq("active_key", activeKey(shopId, orderNo)).last("LIMIT 1"));
    }

    private boolean reusable(WechatJsapiPaymentAttemptEntity a, int amountFen, String openid, String merchantId) {
        return a != null && "ACTIVE".equals(a.getStatus()) && "NOTPAY".equals(a.getTrade_state())
                && StringUtils.hasText(a.getPrepay_id()) && Objects.equals(a.getAmount_fen(), amountFen)
                && Objects.equals(a.getPayer_openid(), openid) && Objects.equals(a.getMerchant_id(), merchantId)
                && a.getExpires_at() != null && a.getExpires_at().after(new Date());
    }

    private void release(WechatJsapiPaymentAttemptEntity attempt, String status, String tradeState) {
        attempt.setStatus(status); attempt.setTrade_state(tradeState); attempt.setActive_key(null);
        attempt.setUpdated_at(new Date()); attemptMapper.updateById(attempt);
    }

    private R response(WechatJsapiPaymentAttemptEntity attempt, Map<String, String> payParams, boolean reused) {
        return R.ok().put("prepay_id", attempt.getPrepay_id()).put("payParams", payParams)
                .put("paymentAttemptId", attempt.getId()).put("outTradeNo", attempt.getOut_trade_no())
                .put("amountFen", attempt.getAmount_fen()).put("expiresAt", attempt.getExpires_at())
                .put("reused", reused);
    }

    private static boolean ok(R result) {
        Object code = result == null ? null : result.get("code");
        return result != null && (code == null || Integer.valueOf(0).equals(code));
    }
    private static R rollback(R result) {
        try {
            TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
        } catch (RuntimeException ignored) {
            // Direct unit invocations do not have an AOP transaction.
        }
        return result;
    }
    private static boolean terminal(String state) {
        return "CLOSED".equals(state) || "REVOKED".equals(state) || "PAYERROR".equals(state);
    }
    private static boolean orderNotExist(WechatNativeApiClient.ApiException ex) {
        return ex != null && ("ORDER_NOT_EXIST".equals(ex.wechatCode)
                || "ORDERNOTEXIST".equals(ex.wechatCode));
    }
    private static String activeKey(Integer shopId, String orderNo) { return shopId + ":" + orderNo; }
    private static String text(Object value) { return value == null ? null : String.valueOf(value); }
}
