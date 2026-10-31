package com.lanf.payment.channel.wechat;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.service.PaymentMerchantConfigService;
import com.lanf.payment.service.PaymentRefundLedger;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentMerchantReadiness;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.payment.support.PaymentMerchantNoUtil;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderService;
import com.lanf.util.SafeLogValue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

/**
 * 微信 JSAPI 统一下单（从 {@code OrderController#executeWxJsapiPrepay} 迁入，语义不变）。
 */
@Component
public class WechatJsapiChannel {

    private static final Logger log = LoggerFactory.getLogger(WechatJsapiChannel.class);

    @Autowired
    private WechatMerchantKeyStore merchantKeyStore;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private OrderPaymentBridge orderPaymentBridge;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private RestTemplate restTemplate;
    @Autowired
    private PaymentMerchantConfigService paymentMerchantConfigService;
    @Autowired
    private PaymentRefundLedger paymentRefundLedger;

    public R createPrepay(Order order, String orderNo, String openid, String takeOut,
                          double paidYuan, String merchantIdInput, String wxDescription) {
        return createPrepay(order, null, orderNo, openid, takeOut, paidYuan, merchantIdInput, wxDescription);
    }

    /**
     * 充值等无订单场景：order 为 null 时须传入 rechargeShopId（与前置校验同源），
     * 否则门店级商户配置会因回退到全店模板（shop_id=0）而解析失败。
     */
    public R createPrepay(Order order, Integer rechargeShopId, String orderNo, String openid, String takeOut,
                          double paidYuan, String merchantIdInput, String wxDescription) {
        String merchantId = StringUtils.hasText(merchantIdInput) ? merchantIdInput : "1";
        Integer shopId = order != null ? order.getShop_id() : rechargeShopId;
        WechatMerchantKeyStore.ResolvedMerchant m = null;
        try {
            
            int totalAmount = com.lanf.util.UserWalletSplitUtil.yuanToFen(paidYuan);
            m = merchantKeyStore.resolveForPay(shopId, merchantId, null);
            if (m.privateKey == null && !StringUtils.hasText(m.mchId)) {
                return R.error(PaymentMerchantReadiness.ENABLE_WECHAT_PAY_HINT);
            }
            if (m.privateKey == null) {
                return R.error("微信支付商户私钥未配置或加载失败，请在运营端检查商户私钥路径与文件权限");
            }
            if (!StringUtils.hasText(m.serialNo) || !StringUtils.hasText(m.mchId)) {
                return R.error("微信支付商户号或 API 证书序列号未配置，请在运营端完善商户配置");
            }
            if (!StringUtils.hasText(m.notifyUrl)) {
                return R.error("微信支付通知地址未配置，请在运营端支付商户中填写 notifyUrl，"
                        + "或配置 app.public-base-url（当前推荐："
                        + paymentMerchantConfigService.defaultWechatPayNotifyUrl() + "）");
            }
            if (!StringUtils.hasText(m.appId)) {
                return R.error("微信支付 appId 未配置，请在运营端支付商户中填写 appId（小程序 appid）");
            }
            if (m.payAuthAudit != null) {
                m.payAuthAudit.orderNo = orderNo;
                log.info("[wx-pay] 统一下单前审计 {}", m.payAuthAudit.toLogLine());
            } else {
                log.info("[wx-pay] 统一下单 shopId={} merchantKey={} mchId={} serialNo={} privateKeyRef={}",
                        shopId, m.merchantKey, m.mchId, m.serialNo, m.privateKeyRefUsed);
            }

            if (order != null) {
                if (m.dbConfigId == null || m.dbConfigVersion == null) {
                    return R.error("微信支付商户配置缺少可绑定版本");
                }
                order.setMerchantId(merchantId);
                order.setMerchant_config_id(m.dbConfigId);
                order.setMerchant_key(m.merchantKey);
                order.setMerchant_config_version(m.dbConfigVersion);
                if (!orderService.updateById(order)) return R.error("保存订单支付商户绑定失败，请重试");
            }

            String outTradeNo = PaymentOrderNoUtil.buildOutTradeNo(orderNo);
            Map<String, Object> requestData = new HashMap<>();
            requestData.put("appid", m.appId);
            requestData.put("mchid", m.mchId);
            requestData.put("description", wxDescription != null ? wxDescription : "老肥油边王");
            requestData.put("out_trade_no", outTradeNo);
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX");
            Calendar calendar = Calendar.getInstance();
            calendar.add(Calendar.MINUTE, 2);
            requestData.put("time_expire", sdf.format(calendar.getTime()));
            requestData.put("notify_url", m.notifyUrl);
            Map<String, Object> amount = new HashMap<>();
            amount.put("total", totalAmount);
            amount.put("currency", "CNY");
            requestData.put("amount", amount);
            Map<String, Object> payer = new HashMap<>();
            payer.put("openid", openid);
            requestData.put("payer", payer);
            requestData.put("support_fapiao", true);

            String nonceStr = WechatPayV3Crypto.generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String bodyJson = objectMapper.writeValueAsString(requestData);
            String urlPath = "/v3/pay/transactions/jsapi";
            String signature = WechatPayV3Crypto.signApiRequest(
                    "POST", urlPath, timestamp, nonceStr, bodyJson, m.privateKey);
            String url = "https://api.mch.weixin.qq.com" + urlPath;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    m.mchId, nonceStr, timestamp, signature, m.serialNo));
            headers.set("Wechatpay-Serial", m.platformPubKeyId);
            HttpEntity<String> requestEntity = new HttpEntity<>(bodyJson, headers);
            String response = restTemplate.postForObject(url, requestEntity, String.class);
            @SuppressWarnings("unchecked")
            Map<String, Object> responseMap = objectMapper.readValue(response, Map.class);
            log.info("处理订单支付，订单号: {}，商户ID: {}", orderNo, merchantId);
            if (responseMap.containsKey("prepay_id")) {
                String prepayId = (String) responseMap.get("prepay_id");
                Map<String, String> payParams = WechatPayV3Crypto.buildMiniProgramPayParams(
                        prepayId, m.appId, m.signer, m.privateKey);
                return R.ok().put("prepay_id", prepayId).put("payParams", payParams);
            }
            return R.error("支付失败: " + response);
        } catch (HttpClientErrorException e) {
            String body = resolveWechatErrorBody(e);
            if (body != null && body.contains("参数与首次请求时不一致")) {
                log.warn("获取prepay_id 请求重入参数不一致，换新单号返回前端，原单号={} bodySummary={}",
                        orderNo, SafeLogValue.summarize(body));
                if (orderNo != null && !orderNo.isEmpty()) {
                    if (order == null) {
                        if (!PaymentMerchantNoUtil.isWxRechargeMerchantNo(orderNo)) {
                            return R.error("请稍后再支付");
                        }
                        MemberRecharge row = memberRechargeService.getOne(
                                new QueryWrapper<MemberRecharge>()
                                        .eq("order_no", orderNo)
                                        .eq("channel", "wechat")
                                        .last("LIMIT 1"));
                        if (row != null) {
                            String newNo = orderPaymentBridge.generateRechargeOrderNo();
                            memberRechargeService.updateOrderNo(orderNo, newNo);
                            log.info("微信充值单换号: {} -> {}, rechargeId={}", orderNo, newNo, row.getId());
                            return R.ok()
                                    .put("newOrderNo", newNo)
                                    .put("orderId", row.getId())
                                    .put("message", "请使用新订单号重新发起支付");
                        }
                        return R.error("请稍后再支付");
                    }
                    Order orderForClose = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
                    if (orderForClose != null) {
                        String newOrderNo = orderPaymentBridge.generateOrderNo();
                        Order updated = orderService.replaceOrderNo(orderNo, newOrderNo);
                        if (updated != null) {
                            log.info("已换新订单号: {} -> {}, orderId={}", orderNo, newOrderNo, updated.getId());
                            return R.ok()
                                    .put("newOrderNo", newOrderNo)
                                    .put("orderId", updated.getId())
                                    .put("message", "请使用新订单号重新发起支付");
                        }
                        log.warn("换新订单号失败，订单不存在: {}", orderNo);
                        return R.error("请稍后再支付");
                    }
                }
                return R.error("请稍后再支付");
            }
            logWechatHttpError(orderNo, shopId, merchantId, m, e, body);
            if (e.getStatusCode() != null && e.getStatusCode().value() == 401) {
                String hint = build401Hint(m, body);
                return R.error("微信支付鉴权失败(401)：" + hint);
            }
            return R.error("支付失败: " + (body != null ? body : e.getMessage()));
        } catch (Exception e) {
            log.error("获取prepay_id异常", e);
            return R.error("支付异常: " + e.getMessage());
        }
    }

    private static String resolveWechatErrorBody(HttpClientErrorException e) {
        String body = e.getResponseBodyAsString();
        if (StringUtils.hasText(body)) {
            return body;
        }
        byte[] bytes = e.getResponseBodyAsByteArray();
        if (bytes != null && bytes.length > 0) {
            return new String(bytes, StandardCharsets.UTF_8);
        }
        return body;
    }

    private void logWechatHttpError(String orderNo, Integer shopId, String merchantId,
                                    WechatMerchantKeyStore.ResolvedMerchant m,
                                    HttpClientErrorException e, String body) {
        HttpStatus status = e.getStatusCode();
        log.error("[wx-pay] 统一下单失败 orderNo={} shopId={} routeMerchantId={} httpStatus={} responseSummary={}",
                orderNo, shopId, merchantId, status, SafeLogValue.summarize(body));
        if (e.getResponseHeaders() != null && !e.getResponseHeaders().isEmpty()) {
            log.error("[wx-pay] 微信响应头 orderNo={} headerCount={}", orderNo, e.getResponseHeaders().size());
        }
        if (m != null && m.payAuthAudit != null) {
            m.payAuthAudit.orderNo = orderNo;
            log.error("[wx-pay] 鉴权配置审计 orderNo={} {}", orderNo, m.payAuthAudit.toLogLine());
            if (!m.payAuthAudit.issues.isEmpty()) {
                log.error("[wx-pay] 401可能原因 orderNo={} issues={}", orderNo, m.payAuthAudit.issues);
            } else if (Boolean.TRUE.equals(m.payAuthAudit.serialMatchesCert)) {
                log.error("[wx-pay] 401 本地 serial 与 PEM 一致但微信仍拒绝，常见：证书已在商户平台作废/未启用、"
                        + "mchId/appId 与证书所属商户不一致、或平台返回 SIGN_ERROR；responseSummary={}",
                        SafeLogValue.summarize(body));
            }
        }
    }

    /**
     * 微信 V3 境内退款（运营后台 {@code OrderController#refund} 使用，密钥来自 DB 商户配置）。
     */
    public R domesticRefund(
            Order order,
            int refundFen,
            int totalFen,
            String reason,
            String idempotencyKey) {
        if (order == null) {
            return R.error("订单不存在");
        }
        String orderNo = order.getOrder_no();
        String merchantId = StringUtils.hasText(order.getMerchantId()) ? order.getMerchantId().trim() : "1";
        WechatMerchantKeyStore.ResolvedMerchant m = resolveOrderMerchant(order, merchantId);
        if (m == null) return R.error("订单绑定的微信商户凭据版本不存在，禁止退款");
        if (m.privateKey == null) {
            return R.error("微信支付商户私钥未配置或加载失败，无法退款，请在运营端检查支付商户配置");
        }
        if (!StringUtils.hasText(m.mchId) || !StringUtils.hasText(m.serialNo)) {
            return R.error("微信支付商户号或证书序列号未配置，无法退款");
        }
        if (!StringUtils.hasText(order.getTransaction_id())) {
            return R.error("订单缺少微信支付单号 transaction_id，无法发起退款");
        }
        if (!StringUtils.hasText(idempotencyKey)) {
            return R.error("微信退款必须提供 idempotency_key");
        }
        if (order.getShop_id() == null || order.getShop_id() <= 0) {
            return R.error("订单缺少门店上下文，无法发起退款");
        }
        try {
            Map<String, Object> req = new HashMap<>();
            req.put("transaction_id", order.getTransaction_id().trim());
            String outRefundNo = PaymentOrderNoUtil.buildOutRefundNo(orderNo, idempotencyKey.trim());
            PaymentRefundLedger.Entry refundEntry = paymentRefundLedger.reserve(
                    order.getShop_id(), orderNo, idempotencyKey.trim(), outRefundNo, refundFen,
                    m.dbConfigId, m.dbConfigVersion, order.getTransaction_id(), m.mchId);
            if (refundEntry.isSuccessful()) {
                return R.ok()
                        .put("idempotent", true)
                        .put("out_refund_no", refundEntry.outRefundNo)
                        .put("refund_amount", refundEntry.appliedFen / 100d);
            }
            if (refundEntry.isRejected()) {
                return R.error(40912,
                        "该退款请求已因同订单存在其他退款而被拒绝，请刷新订单后重新发起");
            }
            req.put("out_refund_no", refundEntry.outRefundNo);
            if (StringUtils.hasText(reason)) {
                req.put("reason", reason.trim());
            }
            Map<String, Object> amount = new HashMap<>();
            amount.put("refund", refundFen);
            amount.put("total", totalFen);
            amount.put("currency", "CNY");
            req.put("amount", amount);
            if (StringUtils.hasText(m.refundNotifyUrl)) {
                req.put("notify_url", m.refundNotifyUrl);
            } else {
                paymentRefundLedger.markRequestFailed(order.getShop_id(), idempotencyKey.trim());
                return R.error("微信商户未配置退款回调地址 refund_notify_url，禁止发起退款（否则退款成功将无法回写订单 refund_amount）；请先在支付商户配置中设置退款回调地址");
            }

            String bodyJson = objectMapper.writeValueAsString(req);
            String urlPath = "/v3/refund/domestic/refunds";
            String nonceStr = WechatPayV3Crypto.generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String signature = WechatPayV3Crypto.signApiRequest(
                    "POST", urlPath, timestamp, nonceStr, bodyJson, m.privateKey);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    m.mchId, nonceStr, timestamp, signature, m.serialNo));
            headers.set("Wechatpay-Serial", m.platformPubKeyId);
            String url = "https://api.mch.weixin.qq.com" + urlPath;
            HttpEntity<String> requestEntity = new HttpEntity<>(bodyJson, headers);

            String response = restTemplate.postForObject(url, requestEntity, String.class);
            if (response == null || response.isEmpty()) {
                return R.error("退款失败：微信返回空响应");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> resp = objectMapper.readValue(response, Map.class);
            if (resp.containsKey("code")) {
                paymentRefundLedger.markRequestFailed(
                        order.getShop_id(), idempotencyKey.trim());
                Object msg = resp.get("message");
                return R.error("退款失败：" + (msg != null ? msg.toString() : resp.get("code").toString()));
            }
            return R.ok()
                    .put("order_no", orderNo)
                    .put("refund_status", resp.get("status"))
                    .put("out_refund_no", resp.get("out_refund_no"))
                    .put("refund_id", resp.get("refund_id"))
                    .put("refund_amount", refundFen / 100.0)
                    .put("message", "退款已提交微信处理；refund_amount、订单状态将在退款成功回调（SUCCESS）后更新");
        } catch (HttpClientErrorException e) {
            paymentRefundLedger.markRequestFailed(
                    order.getShop_id(), idempotencyKey.trim());
            String body = resolveWechatErrorBody(e);
            log.error("[wx-pay] 退款请求失败 orderNo={} status={} responseSummary={}",
                    orderNo, e.getStatusCode(), SafeLogValue.summarize(body));
            return R.error("退款失败：" + (body != null ? body : e.getMessage()));
        } catch (Exception e) {
            log.error("[wx-pay] 退款异常 orderNo={}", orderNo, e);
            return R.error("退款异常：" + e.getMessage());
        }
    }

    /**
     * 查询微信退款单（GET /v3/refund/domestic/refunds/{out_refund_no}），用于退款回调丢失后的补偿对账。
     * 成功时 R 携带 status（SUCCESS/CLOSED/ABNORMAL/PROCESSING）、refund_id、amount_refund_fen。
     */
    public R queryDomesticRefund(Order order, String outRefundNo) {
        if (order == null || !StringUtils.hasText(outRefundNo)) {
            return R.error("查询退款参数无效");
        }
        String merchantId = StringUtils.hasText(order.getMerchantId()) ? order.getMerchantId().trim() : "1";
        WechatMerchantKeyStore.ResolvedMerchant m = resolveOrderMerchant(order, merchantId);
        if (m == null) return R.error("订单绑定的微信商户凭据版本不存在，无法查询退款");
        if (m.privateKey == null || !StringUtils.hasText(m.mchId) || !StringUtils.hasText(m.serialNo)) {
            return R.error("微信支付商户私钥/商户号/证书序列号未配置，无法查询退款");
        }
        try {
            String urlPath = "/v3/refund/domestic/refunds/" + outRefundNo.trim();
            String nonceStr = WechatPayV3Crypto.generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String signature = WechatPayV3Crypto.signApiRequest(
                    "GET", urlPath, timestamp, nonceStr, "", m.privateKey);
            HttpHeaders headers = new HttpHeaders();
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    m.mchId, nonceStr, timestamp, signature, m.serialNo));
            String url = "https://api.mch.weixin.qq.com" + urlPath;
            HttpEntity<String> requestEntity = new HttpEntity<>(headers);
            String response = restTemplate.exchange(
                    url, HttpMethod.GET, requestEntity, String.class).getBody();
            if (response == null || response.isEmpty()) {
                return R.error("退款查询失败：微信返回空响应");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> resp = objectMapper.readValue(response, Map.class);
            if (resp.containsKey("code")) {
                Object msg = resp.get("message");
                return R.error("退款查询失败：" + (msg != null ? msg.toString() : resp.get("code").toString()));
            }
            Object amountObj = resp.get("amount");
            int amountRefundFen = 0;
            if (amountObj instanceof Map) {
                Object refundVal = ((Map<?, ?>) amountObj).get("refund");
                if (refundVal instanceof Number) {
                    amountRefundFen = ((Number) refundVal).intValue();
                }
            }
            return R.ok()
                    .put("out_refund_no", outRefundNo.trim())
                    .put("status", resp.get("status") != null ? resp.get("status").toString() : "")
                    .put("refund_id", resp.get("refund_id") != null ? resp.get("refund_id").toString() : "")
                    .put("amount_refund_fen", amountRefundFen);
        } catch (HttpClientErrorException e) {
            String body = resolveWechatErrorBody(e);
            log.error("[wx-pay] 退款查询失败 outRefundNo={} status={} responseSummary={}",
                    outRefundNo, e.getStatusCode(), SafeLogValue.summarize(body));
            return R.error("退款查询失败：" + (body != null ? body : e.getMessage()));
        } catch (Exception e) {
            log.error("[wx-pay] 退款查询异常 outRefundNo={}", outRefundNo, e);
            return R.error("退款查询异常：" + e.getMessage());
        }
    }

    private WechatMerchantKeyStore.ResolvedMerchant resolveOrderMerchant(Order order, String merchantId) {
        if (order.getMerchant_config_id() != null && order.getMerchant_config_version() != null) {
            return merchantKeyStore.resolveBound(
                    order.getMerchant_config_id(), order.getMerchant_config_version(), order.getShop_id());
        }
        return merchantKeyStore.resolveForPay(order.getShop_id(), merchantId, null);
    }

    private static String build401Hint(WechatMerchantKeyStore.ResolvedMerchant m, String wxBody) {
        if (StringUtils.hasText(wxBody)) {
            return "微信返回：" + wxBody.trim();
        }
        if (m != null && m.payAuthAudit != null && !m.payAuthAudit.issues.isEmpty()) {
            return String.join("；", m.payAuthAudit.issues)
                    + "。请核对 t_payment_merchant_config 的 serial_no 与 private_key_ref 为同一套 API 证书";
        }
        if (m != null && m.payAuthAudit != null && Boolean.TRUE.equals(m.payAuthAudit.serialMatchesCert)) {
            return "本地私钥与 serial_no 文件自检一致，但微信商户平台可能已作废该证书或未绑定 appId="
                    + m.appId + "、mchId=" + m.mchId
                    + "。请登录 pay.weixin.qq.com → 账户中心 → API安全 核对证书状态并重新下载 apiclient_key/cert；"
                    + "详见日志 [wx-pay] wxBody";
        }
        return "商户 API 证书序列号(serialNo)须与私钥成对，且 mchId/appId 与商户平台一致；详见日志 [wx-pay]";
    }
}
