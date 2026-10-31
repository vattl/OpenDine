package com.lanf.payment.notify;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.channel.wechat.WechatPayV3Crypto;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import com.lanf.payment.entity.WechatJsapiPaymentAttemptEntity;
import com.lanf.payment.mapper.WechatNativePaymentAttemptMapper;
import com.lanf.payment.service.WechatPaymentSuccessService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.payment.support.PaymentMerchantNoUtil;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.service.IOrderService;
import com.lanf.util.SafeLogValue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StreamUtils;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

/**
 * 微信支付回调（从 {@code OrderController#paymentHandlePaymentNotify} 迁入）。
 */
@Component
public class WechatPaymentNotifyHandler {

    private static final Logger log = LoggerFactory.getLogger(WechatPaymentNotifyHandler.class);

    @Autowired
    private WechatMerchantKeyStore merchantKeyStore;
    @Autowired
    private PaymentNotifyState paymentNotifyState;
    @Autowired
    private WechatMemberRechargeNotifyHandler memberRechargeNotifyHandler;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private WechatPaymentSuccessService paymentSuccessService;
    @Autowired
    private WechatNativePaymentAttemptMapper nativeAttemptMapper;
    @Autowired
    private WechatJsapiPaymentService jsapiPaymentService;

    public void handle(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setContentType("application/json;charset=UTF-8");
        PrintWriter out = response.getWriter();
        try {
            byte[] bodyBytes = StreamUtils.copyToByteArray(request.getInputStream());
            String body = new String(bodyBytes, StandardCharsets.UTF_8);
            log.info("event=wechat_payment_callback_received bodySummary={}", SafeLogValue.summarize(body));

            WechatMerchantKeyStore.NotifyContext ctx = merchantKeyStore.resolveNotifyContext(request, body);
            if (ctx == null) {
                out.write("{\"code\":\"FAIL\",\"message\":\"签名验证失败\"}");
                return;
            }
            if (!ctx.signatureValid) {
                log.error("微信支付回调签名验证失败");
                out.write("{\"code\":\"FAIL\",\"message\":\"签名验证失败\"}");
                return;
            }
            String merchantId = ctx.legacyMerchantId;

            @SuppressWarnings("unchecked")
            Map<String, Object> notifyData = objectMapper.readValue(body, Map.class);
            String notifyId = (String) notifyData.get("id");
            String eventType = (String) notifyData.get("event_type");
            String resourceType = (String) notifyData.get("resource_type");

            if (!"encrypt-resource".equals(resourceType)) {
                log.error("不支持的资源类型: {}", resourceType);
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的资源类型\"}");
                return;
            }

            if ("TRANSACTION.FAIL".equals(eventType) || "TRANSACTION.CLOSED".equals(eventType)) {
                handleFailOrClosed(out, notifyData, ctx.apiV3KeyCandidates);
                return;
            }

            if (!"TRANSACTION.SUCCESS".equals(eventType)) {
                log.info("非支付成功事件，不做处理: {}", eventType);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            @SuppressWarnings("unchecked")
            Map<String, Object> resource = (Map<String, Object>) notifyData.get("resource");
            if (resource == null) {
                log.error("回调报文中resource字段不存在");
                out.write("{\"code\":\"FAIL\",\"message\":\"资源信息缺失\"}");
                return;
            }
            String algorithm = (String) resource.get("algorithm");
            if (!"AEAD_AES_256_GCM".equals(algorithm)) {
                log.error("不支持的加密算法: {}", algorithm);
                out.write("{\"code\":\"FAIL\",\"message\":\"不支持的加密算法\"}");
                return;
            }

            String ciphertext = (String) resource.get("ciphertext");
            String associatedData = (String) resource.get("associated_data");
            String nonce = (String) resource.get("nonce");
            String decryptData = decryptNotifyResource(ciphertext, associatedData, nonce, ctx.apiV3KeyCandidates);
            if (decryptData == null) {
                log.error("回调报文解密失败（APIv3 密钥不匹配）");
                out.write("{\"code\":\"FAIL\",\"message\":\"解密失败\"}");
                return;
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> paymentResult = objectMapper.readValue(decryptData, Map.class);
            String outTradeNo = (String) paymentResult.get("out_trade_no");
            WechatNativePaymentAttemptEntity nativeAttempt = nativeAttemptMapper.selectOne(
                    new QueryWrapper<WechatNativePaymentAttemptEntity>()
                            .eq("out_trade_no", outTradeNo).last("LIMIT 1"));
            WechatJsapiPaymentAttemptEntity jsapiAttempt = nativeAttempt == null
                    ? jsapiPaymentService.findByOutTradeNo(outTradeNo) : null;
            String orderNo = nativeAttempt != null ? nativeAttempt.getOrder_no()
                    : jsapiAttempt != null ? jsapiAttempt.getOrder_no()
                    : PaymentMerchantNoUtil.parseOrderNoFromOutTradeNo(outTradeNo);

            if (PaymentMerchantNoUtil.isWxRechargeMerchantNo(orderNo)) {
                memberRechargeNotifyHandler.handle(out, notifyId, orderNo, outTradeNo, paymentResult);
                return;
            }

            Order order = loadOrderWithRetry(orderNo, outTradeNo, out);
            if (order == null) {
                return;
            }

            Boolean alreadyProcessed = paymentNotifyState.getProcessed(notifyId);
            if (alreadyProcessed != null && alreadyProcessed) {
                log.info("通知已处理，直接返回成功: {}", notifyId);
                out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                return;
            }

            Integer expectedAmount = nativeAttempt != null ? nativeAttempt.getAmount_fen()
                    : jsapiAttempt != null ? jsapiAttempt.getAmount_fen() : null;
            String resolvedMerchantId = nativeAttempt != null ? nativeAttempt.getMerchant_id()
                    : jsapiAttempt != null ? jsapiAttempt.getMerchant_id() : merchantId;
            Integer expectedShopId = nativeAttempt != null ? nativeAttempt.getShop_id()
                    : jsapiAttempt != null ? jsapiAttempt.getShop_id() : null;
            String actualTradeType = paymentResult.get("trade_type") == null
                    ? null : String.valueOf(paymentResult.get("trade_type"));
            if ((nativeAttempt != null && !"NATIVE".equals(actualTradeType))
                    || (jsapiAttempt != null && !"JSAPI".equals(actualTradeType))) {
                if (jsapiAttempt != null) {
                    WechatPaymentSuccessService.ApplyResult mismatch =
                            WechatPaymentSuccessService.ApplyResult.error("TRADE_TYPE_MISMATCH", "交易类型不匹配");
                    jsapiPaymentService.markCallbackResult(jsapiAttempt, paymentResult, mismatch);
                }
                out.write("{\"code\":\"FAIL\",\"message\":\"交易类型不匹配\"}");
                return;
            }
            if (jsapiAttempt != null && !payerMatches(jsapiAttempt, paymentResult)) {
                WechatPaymentSuccessService.ApplyResult mismatch =
                        WechatPaymentSuccessService.ApplyResult.error("PAYER_MISMATCH", "支付用户不匹配");
                jsapiPaymentService.markCallbackResult(jsapiAttempt, paymentResult, mismatch);
                out.write("{\"code\":\"FAIL\",\"message\":\"支付用户不匹配\"}");
                return;
            }
            WechatPaymentSuccessService.ApplyResult applied = paymentSuccessService.apply(
                    orderNo, outTradeNo, paymentResult, resolvedMerchantId, expectedAmount, expectedShopId);
            if (jsapiAttempt != null) {
                jsapiPaymentService.markCallbackResult(jsapiAttempt, paymentResult, applied);
            }
            if (!applied.success) {
                log.error("微信支付回调入账拒绝 orderNo={} code={}", orderNo, applied.code);
                out.write("{\"code\":\"FAIL\",\"message\":\"" + applied.message + "\"}");
                return;
            }
            if (nativeAttempt != null) {
                nativeAttempt.setStatus("SUCCESS");
                nativeAttempt.setTrade_state("SUCCESS");
                nativeAttempt.setTransaction_id(String.valueOf(paymentResult.get("transaction_id")));
                nativeAttempt.setSuccess_time(new java.util.Date());
                nativeAttempt.setActive_key(null);
                nativeAttempt.setUpdated_at(new java.util.Date());
                nativeAttemptMapper.updateById(nativeAttempt);
            }

            paymentNotifyState.markProcessed(notifyId);
            out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
        } catch (Exception e) {
            log.error("处理回调通知异常", e);
            out.write("{\"code\":\"FAIL\",\"message\":\"处理异常\"}");
        } finally {
            out.flush();
            out.close();
        }
    }

    private static boolean payerMatches(WechatJsapiPaymentAttemptEntity attempt, Map<String, Object> payment) {
        Object payer = payment.get("payer");
        if (!(payer instanceof Map)) return false;
        Object openid = ((Map<?, ?>) payer).get("openid");
        return openid != null && openid.toString().equals(attempt.getPayer_openid());
    }

    private void handleFailOrClosed(PrintWriter out, Map<String, Object> notifyData, List<String> apiV3KeyCandidates)
            throws Exception {
        @SuppressWarnings("unchecked")
        Map<String, Object> resourceFail = (Map<String, Object>) notifyData.get("resource");
        if (resourceFail != null && "AEAD_AES_256_GCM".equals(resourceFail.get("algorithm"))) {
            String ciphertextFail = (String) resourceFail.get("ciphertext");
            String associatedDataFail = (String) resourceFail.get("associated_data");
            String nonceFail = (String) resourceFail.get("nonce");
            if (ciphertextFail != null && associatedDataFail != null && nonceFail != null) {
                try {
                    String decryptFail = decryptNotifyResource(
                            ciphertextFail, associatedDataFail, nonceFail, apiV3KeyCandidates);
                    if (decryptFail == null) {
                        out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
                        return;
                    }
                    @SuppressWarnings("unchecked")
                    Map<String, Object> decMap = objectMapper.readValue(decryptFail, Map.class);
                    String outTradeNoFail = (String) decMap.get("out_trade_no");
                    if (outTradeNoFail != null && !outTradeNoFail.isEmpty()) {
                        jsapiPaymentService.markClosedByOutTradeNo(
                                outTradeNoFail, decMap.get("trade_state") == null
                                        ? "CLOSED" : String.valueOf(decMap.get("trade_state")));
                        String orderNoFail = PaymentMerchantNoUtil.parseOrderNoFromOutTradeNo(outTradeNoFail);
                        if (!PaymentMerchantNoUtil.isWxRechargeMerchantNo(orderNoFail)) {
                            UserCoupon uc = userCouponMapper.selectOne(
                                    new QueryWrapper<UserCoupon>().eq("order_no", orderNoFail).last("LIMIT 1"));
                            if (uc != null) {
                                uc.setOrder_no(null);
                                uc.setUse_time(null);
                                uc.setStatus(0);
                                userCouponMapper.updateById(uc);
                                log.info("支付未成功，优惠券已退回未使用: order_no={}, user_coupon_id={}",
                                        orderNoFail, uc.getId());
                            }
                        }
                    }
                } catch (Exception e) {
                    log.warn("支付失败/关单回调解密或回退优惠券异常: {}", e.getMessage());
                }
            }
        }
        out.write("{\"code\":\"SUCCESS\",\"message\":\"OK\"}");
    }

    private String decryptNotifyResource(String ciphertext, String associatedData, String nonce,
                                         List<String> apiV3KeyCandidates) {
        if (apiV3KeyCandidates == null || apiV3KeyCandidates.isEmpty()) {
            return null;
        }
        for (String key : apiV3KeyCandidates) {
            if (!StringUtils.hasText(key)) {
                continue;
            }
            try {
                return WechatPayV3Crypto.decryptAesGcm(ciphertext, associatedData, nonce, key.trim());
            } catch (Exception e) {
                log.debug("APIv3 密钥候选解密失败，尝试下一个: {}", e.getMessage());
            }
        }
        return null;
    }

    private Order loadOrderWithRetry(String orderNo, String outTradeNo, PrintWriter out) throws IOException {
        int maxRetries = 10;
        int retryCount = 0;
        while (retryCount < maxRetries) {
            Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
            if (order != null) {
                return order;
            }
            retryCount++;
            log.info("第{}次查询未找到订单: {}", retryCount, outTradeNo);
            try {
                Thread.sleep(500);
            } catch (InterruptedException e) {
                log.error("查询订单时线程中断", e);
                Thread.currentThread().interrupt();
                break;
            }
        }
        log.error("经过{}次查询仍未找到对应的订单: {} (out_trade_no={})", maxRetries, orderNo, outTradeNo);
        out.write("{\"code\":\"FAIL\",\"message\":\"订单不存在\"}");
        return null;
    }
}
