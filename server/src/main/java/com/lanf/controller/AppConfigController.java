package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.InviteFirstOrderRewardSettings;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.SystemConfigMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * C 端系统配置接口（openapi 可选项）。
 */
@RestController
@RequestMapping("/config")
public class AppConfigController {

    @Autowired
    private SystemConfigMapper systemConfigMapper;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Autowired
    private InviteFirstOrderRewardSettings inviteFirstOrderRewardSettings;
    @Autowired
    private PaymentCapabilityService paymentCapabilityService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Value("${weixin.notify-url:}")
    private String parkingUrl;
    @Value("${weixin.subscribe-templates.order-status:}")
    private String orderStatusTemplateId;
    @Value("${weixin.subscribe-templates.pickup-notice:}")
    private String pickupNoticeTemplateId;
    @Value("${weixin.subscribe-templates.coupon-granted:}")
    private String couponGrantedTemplateId;
    @Value("${weixin.subscribe-templates.coupon-expiring:}")
    private String couponExpiringTemplateId;

    @GetMapping("/contact")
    public R contact() {
        String phone = getConfigOrDefault("contact.phone", "");
        String workTime = getConfigOrDefault("contact.workTime", "");
        String parking = getConfigOrDefault("contact.parkingUrl", parkingUrl);
        return R.ok()
                .put("contactPhone", phone)
                .put("workTime", workTime)
                .put("parkingUrl", parking);
    }

    /** Template IDs used by wx.requestSubscribeMessage. */
    @GetMapping("/subscribe-templates")
    public R subscribeTemplates() {
        String orderStatus = getConfigOrDefault("weixin.subscribeTemplates.orderStatus", orderStatusTemplateId);
        String pickupNotice = getConfigOrDefault("weixin.subscribeTemplates.pickupNotice", pickupNoticeTemplateId);
        Map<String, String> templates = new LinkedHashMap<>();
        templates.put("orderStatus", orderStatus);
        templates.put("pickupNotice", pickupNotice);
        String couponGranted = getConfigOrDefault("weixin.subscribeTemplates.couponGranted",
                couponGrantedTemplateId != null ? couponGrantedTemplateId : "");
        templates.put("couponGranted", couponGranted);
        String couponExpiring = getConfigOrDefault("weixin.subscribeTemplates.couponExpiring",
                couponExpiringTemplateId != null ? couponExpiringTemplateId : "");
        templates.put("couponExpiring", couponExpiring);
        List<String> templateIds = Arrays.asList(orderStatus, pickupNotice);
        return R.ok().put("templates", templates).put("tmplIds", templateIds)
                .put("subscribeTemplateId1", orderStatus).put("subscribeTemplateId2", pickupNotice);
    }

    @GetMapping("/app")
    public R app() {
        return R.ok()
                .put("privacyVersion", getConfigOrDefault("app.privacyVersion", "1.0.0"))
                .put("serviceVersion", getConfigOrDefault("app.serviceVersion", "1.0.0"))
                .put("parkingUrl", getConfigOrDefault("contact.parkingUrl", parkingUrl));
    }

    /**
     * 微信统一下单夜间九折规则（只读，按门店；修改走 {@code PUT /admin/payment/ninefold} 或兼容 {@code PUT /admin/config/wechat-prepay-ninefold}）。
     */
    @GetMapping("/wechat-prepay-ninefold")
    public R wechatPrepayNinefold(@RequestParam(name = "shop_id", required = false) Integer shopId,
                                  @RequestParam(name = "shop_code", required = false) String shopCode,
                                  @RequestParam(name = "order_no", required = false) String orderNo,
                                  @RequestParam(name = "orderNo", required = false) String orderNoCamel) {
        try {
            Integer resolved = resolvePaymentCapabilitiesShopId(shopId, shopCode, orderNo, orderNoCamel);
            return R.ok(paymentNinefoldService.toPublicMap(resolved));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 邀请好友首单余额返利规则（只读；修改走 {@code PUT /admin/config/invite-first-order-balance-reward}）。
     */
    @GetMapping("/invite-first-order-balance-reward")
    public R inviteFirstOrderBalanceReward() {
        return R.ok(inviteFirstOrderRewardSettings.toPublicMap());
    }

    /**
     * 门店支付能力（线上开关、渠道、线下收款码；含夜间九折只读配置）。
     * 订单详情等场景须按<strong>下单门店</strong>查询：传 {@code order_no}，或传与订单一致的 {@code shop_id}（优先于 {@code X-Shop-Id}）。
     */
    @GetMapping("/payment-capabilities")
    public R paymentCapabilities(@RequestParam(name = "shop_id", required = false) Integer shopId,
                                 @RequestParam(name = "shop_code", required = false) String shopCode,
                                 @RequestParam(name = "order_no", required = false) String orderNo,
                                 @RequestParam(name = "orderNo", required = false) String orderNoCamel) {
        try {
            Integer resolved = resolvePaymentCapabilitiesShopId(shopId, shopCode, orderNo, orderNoCamel);
            return R.ok(paymentCapabilityService.toPublicMap(resolved));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    private Integer resolvePaymentCapabilitiesShopId(Integer shopId, String shopCode,
                                                     String orderNo, String orderNoCamel) {
        String on = firstNonBlank(orderNo, orderNoCamel);
        if (StringUtils.hasText(on)) {
            Order order = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", on.trim())
                    .orderByDesc("id")
                    .last("LIMIT 1"));
            if (order == null) {
                throw new RuntimeException("订单不存在");
            }
            Integer oid = order.getShop_id();
            return oid != null && oid > 0 ? oid : 1;
        }
        String code = shopCode != null ? shopCode.trim() : null;
        Integer resolved = ShopChainSupport.resolveShopChainPreferParam(httpServletRequest, shopId, code,
                shopService::requireActiveShopIdByCode);
        if (resolved == null) {
            resolved = 0;
        }
        return resolved;
    }

    private static String firstNonBlank(String a, String b) {
        if (StringUtils.hasText(a)) {
            return a.trim();
        }
        if (StringUtils.hasText(b)) {
            return b.trim();
        }
        return null;
    }

    private String getConfigOrDefault(String key, String def) {
        SystemConfig one = systemConfigMapper.selectOne(new QueryWrapper<SystemConfig>().eq("config_key", key));
        if (one == null || one.getConfig_value() == null) {
            return def;
        }
        return one.getConfig_value();
    }
}
