package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.annotation.NoAuth;
import com.lanf.dto.OfflineCollectTokenPayload;
import com.lanf.entity.R;
import com.lanf.entity.Order;
import com.lanf.entity.Shop;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.OfflineCollectTokenService;
import com.lanf.service.PersonalPaymentWebhookService;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.util.OfflineCollectQrCodec;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopChainSupport;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;

/**
 * 线下收款：服务端将门店已解码的收款串（如微信 {@code wxp://}、支付宝 {@code https://qr.alipay.com/...}）生成二维码图供对方扫。
 * {@link #jump(String, HttpServletRequest, HttpServletResponse)} 仍保留短时 token 跳转备用。
 */
@RestController
@RequestMapping("/pay/offline-collect")
@RequiredArgsConstructor
public class PayOfflineCollectController {

    private static final String MERCHANT_TWO_WECHAT_PAYLOAD =
            "wxp://f2f05JKIRZqDSA-IOrNU9MXzGYgNaYLIYzU5uvp8OAKYJVA";

    private static final Logger log = LoggerFactory.getLogger(PayOfflineCollectController.class);

    private final OfflineCollectTokenService tokenService;
    private final IShopService shopService;
    private final ObjectMapper objectMapper;
    private final PaymentCapabilityService paymentCapabilityService;
    private final CashierCollectionIntentService collectionIntentService;
    private final PersonalPaymentWebhookService personalPaymentWebhookService;
    private final IOrderService orderService;

    @Value("${app.public-base-url:}")
    private String configuredPublicBaseUrl;

    /**
     * 生成收款二维码（PNG Base64）：矩阵内容为门店 {@code offline_collect_*_payload}（与扫运营上传的原收款码等价），
     * 适合用<strong>微信/支付宝扫一扫</strong>直接调起官方收款页；不依赖 H5 跳转 {@code wxp://}。
     * 需请求头 {@code X-Shop-Id}（或与小程序一致的 body {@code shop_id}）。
     */
    @PostMapping(value = "/temp-qrcode", produces = MediaType.APPLICATION_JSON_VALUE)
    public R tempQrcode(@RequestBody(required = false) Map<String, Object> body,
                                             HttpServletRequest request) throws Exception {
        Integer shopId = resolveShopId(request, body);
        if (shopId == null || shopId <= 0) {
            return R.error(400, "请携带 X-Shop-Id 或 body.shop_id 指定门店");
        }
        String channel = body != null && body.get("channel") != null ? body.get("channel").toString().trim() : "wechat";
        if (!"wechat".equalsIgnoreCase(channel) && !"alipay".equalsIgnoreCase(channel)) {
            return R.error(400, "channel 仅支持 wechat 或 alipay");
        }
        channel = channel.toLowerCase();
        String orderNo = body != null && body.get("order_no") != null
                ? body.get("order_no").toString().trim() : "";
        String sessionId = body != null && body.get("session_id") != null
                ? body.get("session_id").toString().trim() : "";
        int amountFen = body != null && body.get("amount_fen") instanceof Number
                ? ((Number) body.get("amount_fen")).intValue() : 0;
        boolean cashierIntent = StringUtils.hasText(orderNo)
                || StringUtils.hasText(sessionId) || amountFen > 0;
        String merchantId = null;
        if (!cashierIntent) {
            try {
                merchantId = resolveMerchantId(body);
            } catch (IllegalArgumentException e) {
                return R.error(400, e.getMessage());
            }
        }
        String personalQrPaymentMethod = "wechat".equals(channel)
                ? PaymentChannelCatalog.OFFLINE_WECHAT_QR
                : PaymentChannelCatalog.OFFLINE_ALIPAY_QR;
        if (!paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, personalQrPaymentMethod)) {
            return R.error(400, "当前门店未启用"
                    + ("wechat".equals(channel) ? "微信收款码" : "支付宝收款码"));
        }
        if (cashierIntent) {
            if (!StringUtils.hasText(orderNo) || !StringUtils.hasText(sessionId)) {
                return R.error(400, "收银出码须同时提供 order_no、session_id");
            }
            Order order = orderService.getOne(new QueryWrapper<Order>()
                    .eq("shop_id", shopId)
                    .eq("order_no", orderNo)
                    .last("LIMIT 1"));
            if (order == null) {
                Order globalOrder = orderService.getOne(new QueryWrapper<Order>()
                        .eq("order_no", orderNo)
                        .last("LIMIT 1"));
                if (globalOrder == null) {
                    return R.error(400, "订单不存在");
                } else {
                    return R.error(400, "订单不属于当前门店");
                }
            }
            if ("success".equalsIgnoreCase(order.getTransac_status())) {
                return R.error(400, "订单已结账");
            }
            if ("cancelled".equalsIgnoreCase(order.getTransac_status())) {
                return R.error(400, "订单已取消");
            }
            if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
                return R.error(400, "订单状态不是未结账状态（当前状态：" + order.getTransac_status() + "）");
            }
            if (amountFen <= 0) {
                amountFen = OrderNetRevenue.netRevenueFen(order);
            }
            if (amountFen <= 0) {
                return R.error(400, "订单待收金额为 ¥0.00，无需生成收款码");
            }
            try {
                merchantId = normalizeMerchantId(order.getMerchantId());
            } catch (IllegalArgumentException e) {
                return R.error(400, "订单 merchantId 配置无效");
            }
            if (!StringUtils.hasText(merchantId)) {
                merchantId = "1";
            }
        }
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            return R.error(404, "门店不存在");
        }
        String payload = resolveCollectPayload(shop, channel, merchantId);
        if (!StringUtils.hasText(payload)) {
            return R.error(400, "门店未配置" + ("wechat".equals(channel) ? "微信" : "支付宝") + "收款码，请先上传");
        }
        payload = payload.trim();
        byte[] png = OfflineCollectQrCodec.encodeQrPng(payload, 320);
        String b64 = Base64.getEncoder().encodeToString(png);
        String token = StringUtils.hasText(merchantId)
                ? tokenService.newToken(shopId, channel, merchantId)
                : tokenService.newToken(shopId, channel);
        String base = resolvePublicBase(request);
        String jumpUrl = base + "/pay/offline-collect/jump?t=" + token;
        if (cashierIntent) {
            try {
                collectionIntentService.reserve(
                        shopId, orderNo, sessionId, channel, amountFen);
            } catch (IllegalArgumentException | IllegalStateException e) {
                return R.error(409, e.getMessage());
            }
        }
        boolean autoSettled = false;
        if (cashierIntent) {
            // 出码补偿：客人先付款、后开码时回调早已过去，向前匹配近期已到账记录直接结账
            try {
                autoSettled = personalPaymentWebhookService.settleByRecentPaid(
                        shopId, orderNo, channel, amountFen, sessionId);
            } catch (Exception e) {
                log.warn("出码补偿匹配异常 orderNo={}: {}", orderNo, e.getMessage());
            }
        }
        R result = R.ok()
                .put("qrImageBase64", b64)
                .put("jumpUrl", jumpUrl)
                .put("expiresInSeconds", OfflineCollectTokenService.TTL_MINUTES * 60)
                .put("channel", channel)
                .put("shopId", shopId);
        if (StringUtils.hasText(merchantId)) {
            result.put("merchantId", merchantId);
        }
        if (cashierIntent) {
            result.put("orderNo", orderNo)
                    .put("sessionId", sessionId)
                    .put("amountFen", amountFen);
        }
        if (autoSettled) {
            result.put("autoSettled", true)
                    .put("settled", true)
                    .put("transac_status", "success");
        }
        return result;
    }

    @PostMapping(value = "/confirm", produces = MediaType.APPLICATION_JSON_VALUE)
    public R confirmCollection(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        Integer shopId = resolveShopId(request, body);
        if (shopId == null || shopId <= 0) {
            return R.error(400, "请携带 X-Shop-Id 指定门店");
        }
        String orderNo = body.get("order_no") != null
                ? body.get("order_no").toString().trim() : "";
        String sessionId = body.get("session_id") != null
                ? body.get("session_id").toString().trim() : "";
        String channel = body.get("channel") != null
                ? body.get("channel").toString().trim().toLowerCase() : "";
        int amountFen = body.get("amount_fen") instanceof Number
                ? ((Number) body.get("amount_fen")).intValue() : 0;
        try {
            int confirmedAmountFen = collectionIntentService.confirm(
                    shopId, orderNo, sessionId, channel, amountFen);
            return R.ok().put("amountFen", confirmedAmountFen);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(409, e.getMessage());
        }
    }

    @PostMapping(value = "/cancel", produces = MediaType.APPLICATION_JSON_VALUE)
    public R cancelCollection(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        Integer shopId = resolveShopId(request, body);
        if (shopId == null || shopId <= 0) {
            return R.error(400, "请携带 X-Shop-Id 指定门店");
        }
        String orderNo = body.get("order_no") != null
                ? body.get("order_no").toString().trim() : "";
        String sessionId = body.get("session_id") != null
                ? body.get("session_id").toString().trim() : "";
        String channel = body.get("channel") != null
                ? body.get("channel").toString().trim().toLowerCase() : "";
        try {
            int released = collectionIntentService.cancelPending(
                    shopId, orderNo, sessionId, channel);
            return R.ok()
                    .put("released", released > 0)
                    .put("releasePolicy", "PENDING_ONLY_CURRENT_SESSION");
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(409, e.getMessage());
        }
    }

    /**
     * 扫码入口：跳转到已配置的微信/支付宝收款串（进入官方「输入金额」流程）。
     * <p>微信内置浏览器对脚本执行的 {@code location.replace('wxp://…')} 常拦截；此处优先使用 <strong>HTTP 302 Location</strong>
     * 由系统跟随打开收款协议；少数容器不支持自定义 scheme 时再回退为可点击 HTML（大号按钮 + 延时 {@code location.href}）。
     */
    @NoAuth
    @GetMapping("/jump")
    public void jump(@RequestParam("t") String token,
                     HttpServletRequest request,
                     HttpServletResponse response) throws Exception {
        Optional<OfflineCollectTokenPayload> op = tokenService.resolve(token);
        if (!op.isPresent()) {
            writeExpiredHtml(response);
            return;
        }
        OfflineCollectTokenPayload p = op.get();
        Shop shop = shopService.getById(p.getShopId());
        if (shop == null) {
            writeExpiredHtml(response);
            return;
        }
        String target = resolveCollectPayload(shop, p.getChannel(), p.getMerchantId());
        if (!StringUtils.hasText(target)) {
            writeExpiredHtml(response);
            return;
        }
        target = target.trim();

        try {
            response.sendRedirect(target);
            return;
        } catch (IllegalStateException | IOException ex) {
            log.warn("offline-collect jump: redirect failed, html fallback: {}", ex.toString());
        }
        writeJumpFallbackHtml(response, target);
    }

    /**
     * 302 不可用时（或部分环境对 wxp:// 的 sendRedirect 异常）：仅依赖用户点击或弱自动跳转。
     */
    private void writeJumpFallbackHtml(HttpServletResponse response, String target) throws IOException {
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType(MediaType.TEXT_HTML_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        String hrefAttr = htmlEscapeAttribute(target);
        String asJson = objectMapper.writeValueAsString(target);
        String html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"/>"
                + "<title>跳转收款</title></head><body style=\"font-family:sans-serif;text-align:center;padding:24px;\">"
                + "<p>正在打开收款…</p>"
                + "<p style=\"margin:28px 0;\"><a style=\"font-size:1.2rem;padding:14px 28px;border-radius:10px;display:inline-block;"
                + "text-decoration:none;background:#07c160;color:#fff;\" href=\"" + hrefAttr + "\">点这里打开收款</a></p>"
                + "<p style=\"color:#888;font-size:0.85rem;\">若自动跳转失败，请务必点击上方按钮（微信会拦截无用户操作的 wxp 跳转）</p>"
                + "<script>(function(){var u=" + asJson + ";setTimeout(function(){"
                + "try{window.location.href=u;}catch(e){}},200);})();</script>"
                + "</body></html>";
        response.getWriter().write(html);
    }

    /** href / meta 用：仅转义 HTML 属性敏感字符，不改变 wxp/https 协议串本身 */
    private static String htmlEscapeAttribute(String raw) {
        if (raw == null) {
            return "";
        }
        return raw.replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;");
    }

    private static void writeExpiredHtml(HttpServletResponse response) throws Exception {
        response.setStatus(410);
        response.setContentType(MediaType.TEXT_HTML_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.getWriter().write("<!DOCTYPE html><html><head><meta charset=\"utf-8\"/><title>已失效</title></head>"
                + "<body style=\"font-family:sans-serif;text-align:center;padding:32px;\">"
                + "<p>二维码已失效（约 3 分钟），请让对方重新生成。</p></body></html>");
    }

    private String resolvePublicBase(HttpServletRequest request) {
        if (StringUtils.hasText(configuredPublicBaseUrl)) {
            return configuredPublicBaseUrl.trim().replaceAll("/+$", "");
        }
        String scheme = request.getScheme();
        String host = request.getServerName();
        int port = request.getServerPort();
        if (("http".equalsIgnoreCase(scheme) && port == 80) || ("https".equalsIgnoreCase(scheme) && port == 443)) {
            return scheme + "://" + host;
        }
        return scheme + "://" + host + ":" + port;
    }

    private static Integer resolveShopId(HttpServletRequest request, Map<String, Object> body) {
        if (body != null && body.get("shop_id") instanceof Number) {
            int v = ((Number) body.get("shop_id")).intValue();
            if (v > 0) {
                return v;
            }
        }
        if (body != null && body.get("shopId") instanceof Number) {
            int v = ((Number) body.get("shopId")).intValue();
            if (v > 0) {
                return v;
            }
        }
        try {
            return ShopChainSupport.parseHeaderShopId(request);
        } catch (Exception e) {
            log.debug("parse shop id: {}", e.getMessage());
            return null;
        }
    }

    private static String resolveMerchantId(Map<String, Object> body) {
        if (body == null) {
            return null;
        }
        String camel = normalizeMerchantId(body.get("merchantId"));
        String snake = normalizeMerchantId(body.get("merchant_id"));
        if (camel != null && snake != null && !camel.equals(snake)) {
            throw new IllegalArgumentException("merchantId 与 merchant_id 不一致");
        }
        return camel != null ? camel : snake;
    }

    private static String normalizeMerchantId(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = raw.toString().trim();
        if (value.isEmpty()) {
            return null;
        }
        if (value.length() > 32 || !value.matches("[A-Za-z0-9_-]+")) {
            throw new IllegalArgumentException("merchantId 格式无效");
        }
        return value;
    }

    private static String resolveCollectPayload(
            Shop shop, String channel, String merchantId) {
        if ("wechat".equals(channel) && "2".equals(merchantId)) {
            return MERCHANT_TWO_WECHAT_PAYLOAD;
        }
        return "alipay".equals(channel)
                ? shop.getOffline_collect_alipay_payload()
                : shop.getOffline_collect_wechat_payload();
    }
}
