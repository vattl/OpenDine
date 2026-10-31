package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentCapabilityEntity;
import com.lanf.payment.mapper.PaymentCapabilityMapper;
import com.lanf.payment.support.PaymentCapabilityMatcher;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.payment.support.PaymentMerchantReadiness;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class PaymentCapabilityService {

    private static final String DEFAULT_DISABLED_MSG = "请联系服务员结账";

    @Autowired
    private PaymentCapabilityMapper capabilityMapper;
    @Autowired
    private PaymentConfigCache configCache;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Lazy
    @Autowired
    private PaymentMerchantConfigService merchantConfigService;

    public PaymentCapabilityEntity loadRowFromDb(int shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        return capabilityMapper.selectOne(new QueryWrapper<PaymentCapabilityEntity>()
                .eq("shop_id", sid)
                .last("LIMIT 1"));
    }

    public ResolvedCapability resolve(Integer shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentCapabilityEntity shopRow = configCache.getCapabilityRow(sid);
        PaymentCapabilityEntity globalRow = sid == PaymentConfigCache.GLOBAL_SHOP_ID
                ? null
                : configCache.getCapabilityRow(PaymentConfigCache.GLOBAL_SHOP_ID);
        if (shopRow == null && sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            shopRow = loadRowFromDb(sid);
            if (shopRow != null) {
                configCache.putCapability(sid, shopRow);
            }
        }
        if (globalRow == null && sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            globalRow = configCache.getCapabilityRow(PaymentConfigCache.GLOBAL_SHOP_ID);
            if (globalRow == null) {
                globalRow = loadRowFromDb(PaymentConfigCache.GLOBAL_SHOP_ID);
                if (globalRow != null) {
                    configCache.putCapability(PaymentConfigCache.GLOBAL_SHOP_ID, globalRow);
                }
            }
        }
        if (shopRow == null && sid == PaymentConfigCache.GLOBAL_SHOP_ID) {
            shopRow = loadRowFromDb(PaymentConfigCache.GLOBAL_SHOP_ID);
            if (shopRow != null) {
                configCache.putCapability(PaymentConfigCache.GLOBAL_SHOP_ID, shopRow);
            }
            globalRow = shopRow;
        }
        boolean merchantReady = merchantConfigService.hasWechatPayReady(sid);
        boolean miniProgramMerchantReady = merchantConfigService.hasWechatMiniProgramPayReady(sid);
        ResolvedCapability r = new ResolvedCapability();
        r.shopId = sid;
        r.wechatMerchantReady = merchantReady;
        r.miniProgramWechatMerchantReady = miniProgramMerchantReady;
        r.miniProgramWechatMissingFields =
                merchantConfigService.getWechatMiniProgramMissingFields(sid);
        boolean onlineStored = resolveBool(shopRow, globalRow, PaymentCapabilityEntity::getOnline_pay_enabled, false);
        boolean wechatStored = resolveBool(shopRow, globalRow, PaymentCapabilityEntity::getWechat_enabled, false);
        boolean balanceStored = resolveBool(shopRow, globalRow, PaymentCapabilityEntity::getBalance_enabled, true);
        r.onlinePayEnabled = onlineStored;
        r.wechatEnabledConfigured = wechatStored;
        r.wechatEnabled = merchantReady && wechatStored;
        r.alipayEnabled = resolveBool(shopRow, globalRow, PaymentCapabilityEntity::getAlipay_enabled, false);
        r.balanceEnabled = balanceStored;
        r.combinedEnabled = resolveBool(shopRow, globalRow, PaymentCapabilityEntity::getCombined_enabled, true);
        r.cashierPayEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_pay_enabled, onlineStored);
        r.cashierWechatEnabledConfigured = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_wechat_enabled, wechatStored);
        r.cashierWechatEnabled = merchantReady && r.cashierWechatEnabledConfigured;
        r.cashierAlipayEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_alipay_enabled, r.alipayEnabled);
        r.cashierBalanceEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_balance_enabled, balanceStored);
        r.cashierCombinedEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_combined_enabled, r.combinedEnabled);
        r.miniProgramPayEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getMini_program_pay_enabled, onlineStored);
        r.miniProgramWechatEnabledConfigured = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getMini_program_wechat_enabled, wechatStored);
        r.miniProgramWechatEnabled =
                miniProgramMerchantReady && r.miniProgramWechatEnabledConfigured;
        r.miniProgramBalanceEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getMini_program_balance_enabled, balanceStored);
        // 收款码开关单一来源 = 收银端 cashier 独立列（D021：废弃 offline_collect_channels 双写/回退）
        Integer qrWechatRaw = resolveNullable(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_wechat_qr_enabled);
        Integer qrAlipayRaw = resolveNullable(shopRow, globalRow,
                PaymentCapabilityEntity::getCashier_alipay_qr_enabled);
        r.cashierWechatQrEnabled = qrWechatRaw != null && intToBool(qrWechatRaw);
        r.cashierAlipayQrEnabled = qrAlipayRaw != null && intToBool(qrAlipayRaw);
        // legacy offlineCollect 结构由收银端收款码实时派生（不再读 offline_collect_enabled/offline_collect_channels 列）
        java.util.List<String> qrModes = new java.util.ArrayList<>();
        if (r.cashierWechatQrEnabled) { qrModes.add("wechat"); }
        if (r.cashierAlipayQrEnabled) { qrModes.add("alipay"); }
        r.offlineCollectEnabled = r.cashierWechatQrEnabled || r.cashierAlipayQrEnabled;
        r.offlineCollectChannels = qrModes;
        r.miniProgramAlipayEnabled = resolveBool(shopRow, globalRow,
                PaymentCapabilityEntity::getMini_program_alipay_enabled, false);
        int cashierBaseCount = (r.cashierWechatEnabled ? 1 : 0)
                + (r.cashierAlipayEnabled ? 1 : 0)
                + (r.cashierBalanceEnabled ? 1 : 0);
        r.combinedAvailable = r.cashierPayEnabled && cashierBaseCount >= 2;
        r.miniProgramWechatAvailable = miniProgramMerchantReady;
        r.disabledMessage = resolveString(shopRow, globalRow, PaymentCapabilityEntity::getDisabled_message,
                DEFAULT_DISABLED_MSG);
        return r;
    }

    public boolean isOnlinePayEnabled(Integer shopId) {
        return isMiniProgramPayEnabled(shopId);
    }

    public boolean isMiniProgramPayEnabled(Integer shopId) {
        return resolve(shopId).miniProgramPayEnabled;
    }

    public boolean isWechatEnabled(Integer shopId) {
        ResolvedCapability r = resolve(shopId);
        return r.miniProgramPayEnabled && r.miniProgramWechatEnabled;
    }

    public boolean isWechatMerchantReady(Integer shopId) {
        return merchantConfigService.hasWechatPayReady(shopId);
    }

    public boolean isAlipayEnabled(Integer shopId) {
        ResolvedCapability r = resolve(shopId);
        return r.cashierPayEnabled && r.cashierAlipayEnabled;
    }

    public boolean isBalanceEnabled(Integer shopId) {
        ResolvedCapability r = resolve(shopId);
        return r.miniProgramPayEnabled && r.miniProgramBalanceEnabled;
    }

    public String getDisabledMessage(Integer shopId) {
        return resolve(shopId).disabledMessage;
    }

    /**
     * 判断指定支付能力/渠道是否在指定门店生效。
     * 支持直接传入响应字段名（如 cashier_wechat_enabled, cashierWechatEnabled）、
     * JSON 路径（如 clients.cashier.channels.wechat, cashier.wechat）、
     * 渠道代号（如 online_wechat, offline_wechat_qr）或业务中文名（如 微信支付, 微信收款码）。
     */
    public boolean isPaymentMethodEnabled(Integer shopId, String paymentMethod) {
        return isCashierPaymentMethodEnabled(shopId, paymentMethod);
    }

    /**
     * 按 clients.cashier.enabled/channels 的保存值判断收银端渠道开关。
     */
    public boolean isCashierConfiguredChannelEnabled(Integer shopId, String channel) {
        if (!StringUtils.hasText(channel)) {
            return false;
        }
        ResolvedCapability r = resolve(shopId);
        if (!r.cashierPayEnabled) {
            return false;
        }
        String normalized = channel.trim().toLowerCase();
        if ("wechat".equals(normalized) || "cashier_wechat".equals(normalized) || "cashierwechatenabled".equals(normalized)) {
            return r.cashierWechatEnabledConfigured;
        }
        if ("alipay".equals(normalized) || "cashier_alipay".equals(normalized) || "cashieralipayenabled".equals(normalized)) {
            return r.cashierAlipayEnabled;
        }
        return false;
    }

    /**
     * 判断收银端支付渠道或配置字段是否在指定门店生效。
     */
    public boolean isCashierPaymentMethodEnabled(Integer shopId, String paymentMethod) {
        if (!StringUtils.hasText(paymentMethod)) {
            return false;
        }
        ResolvedCapability r = resolve(shopId);
        if (PaymentCapabilityMatcher.isMatchEnabled(r, paymentMethod)) {
            return true;
        }
        String code = PaymentChannelCatalog.codeFromPaymentMethod(paymentMethod);
        if (code != null && PaymentCapabilityMatcher.isMatchEnabled(r, code)) {
            return true;
        }
        return false;
    }

    /**
     * 直接通过字段名、属性名或路径判断任一支付能力开关是否生效。
     */
    public boolean isCapabilityEnabled(Integer shopId, String key) {
        return PaymentCapabilityMatcher.isMatchEnabled(resolve(shopId), key);
    }

    public Map<String, Object> toPublicMap(Integer shopId) {
        ResolvedCapability r = resolve(shopId);
        boolean miniEnabled = r.miniProgramPayEnabled;
        boolean cashierEnabled = r.cashierPayEnabled;
        boolean legacyWechat = miniEnabled && r.miniProgramWechatEnabled;
        boolean legacyBalance = miniEnabled && r.miniProgramBalanceEnabled;
        boolean legacyAlipay = cashierEnabled && r.cashierAlipayEnabled;
        Map<String, Object> channels = new LinkedHashMap<>();
        Map<String, Object> wechat = new LinkedHashMap<>();
        wechat.put("enabled", legacyWechat);
        channels.put("wechat", wechat);
        Map<String, Object> alipay = new LinkedHashMap<>();
        alipay.put("enabled", legacyAlipay);
        channels.put("alipay", alipay);
        Map<String, Object> balance = new LinkedHashMap<>();
        balance.put("enabled", legacyBalance);
        channels.put("balance", balance);
        Map<String, Object> combined = new LinkedHashMap<>();
        int enabledOnlineCount = (r.cashierWechatEnabled ? 1 : 0)
                + (r.cashierAlipayEnabled ? 1 : 0)
                + (r.cashierBalanceEnabled ? 1 : 0);
        boolean combinedEffective = cashierEnabled
                && r.cashierCombinedEnabled && enabledOnlineCount >= 2;
        combined.put("enabled", combinedEffective);
        channels.put("combined", combined);
        Map<String, Object> offline = new LinkedHashMap<>();
        offline.put("enabled", r.offlineCollectEnabled);
        offline.put("modes", r.offlineCollectChannels);
        channels.put("offlineCollect", offline);

        Map<String, Object> out = new LinkedHashMap<>();
        // D017：C 端 /config 精简——兼容字段仅保留 wechatMerchantReady/channels/onlinePayEnabled，
        // 其余（effective*/hint/missing/canEnable*/globalOnlinePayEnabled）移入 B 端 admin 视图
        out.put("shopId", r.shopId);
        out.put("wechatMerchantReady", r.wechatMerchantReady);
        out.put("onlinePayEnabled", miniEnabled);
        out.put("disabledMessage", r.disabledMessage);
        out.put("channels", channels);
        out.put("clients", clientCapabilities(r, false));
        out.put("nineFold", paymentNinefoldService.toPublicMap(r.shopId));
        return out;
    }

    private static String miniProgramWechatEnableHint(ResolvedCapability r) {
        if (r.miniProgramWechatMerchantReady) {
            return "";
        }
        String hint = PaymentMerchantReadiness.ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT;
        if (r.miniProgramWechatMissingFields == null || r.miniProgramWechatMissingFields.isEmpty()) {
            return hint;
        }
        return hint + "；缺少：" + String.join(", ", r.miniProgramWechatMissingFields);
    }

    // D021：收款码可用性单一来源 = 收银端收款码独立开关（offlineCollect 为派生展示）
    private static boolean offlineWechatEnabled(ResolvedCapability r) {
        return r.cashierWechatQrEnabled;
    }

    private static boolean offlineAlipayEnabled(ResolvedCapability r) {
        return r.cashierAlipayQrEnabled;
    }

    private static Map<String, Object> clientCapabilities(ResolvedCapability r, boolean admin) {
        Map<String, Object> clients = new LinkedHashMap<>();

        boolean cashierEnabled = r.cashierPayEnabled;
        boolean cashierWechat = cashierEnabled && r.cashierWechatEnabled;
        boolean cashierAlipay = cashierEnabled && r.cashierAlipayEnabled;
        boolean cashierBalance = cashierEnabled && r.cashierBalanceEnabled;
        int cashierBaseCount = 1
                + (cashierWechat ? 1 : 0)
                + (cashierAlipay ? 1 : 0)
                + (cashierBalance ? 1 : 0);
        boolean cashierCombined = cashierEnabled && r.cashierCombinedEnabled && cashierBaseCount >= 2;
        Map<String, Object> cashier = new LinkedHashMap<>();
        cashier.put("enabled", cashierEnabled);
        Map<String, Object> cashierChannels = channelFlags(
                r.cashierWechatEnabledConfigured,
                r.cashierAlipayEnabled,
                r.cashierBalanceEnabled,
                r.cashierCombinedEnabled);
        cashier.put("channels", cashierChannels);
        cashier.put("wechatMerchantReady", r.wechatMerchantReady);
        if (admin) {
            cashier.put("effectiveEnabled", cashierEnabled);
            cashier.put("effectiveChannels",
                    channelFlags(cashierWechat, cashierAlipay, cashierBalance, cashierCombined));
            cashier.put("wechatReadyHint",
                    r.wechatMerchantReady ? "" : PaymentMerchantReadiness.ENABLE_WECHAT_PAY_HINT);
            cashier.put("wechat_qr", r.cashierWechatQrEnabled);
            cashier.put("alipay_qr", r.cashierAlipayQrEnabled);
        }
        Map<String, Object> cashierStates = new LinkedHashMap<>();
        cashierStates.put("wechat", channelState(r.cashierWechatEnabledConfigured, true, ""));
        cashierStates.put("alipay", channelState(r.cashierAlipayEnabled, true, ""));
        cashierStates.put("balance", channelState(r.cashierBalanceEnabled, true, ""));
        cashierStates.put("combined", channelState(r.cashierCombinedEnabled, r.combinedAvailable,
                r.combinedAvailable ? "" : "组合支付需至少 2 个基础渠道生效"));
        cashierStates.put("wechat_qr", channelState(r.cashierWechatQrEnabled, true, ""));
        cashierStates.put("alipay_qr", channelState(r.cashierAlipayQrEnabled, true, ""));
        cashier.put("channelStates", cashierStates);
        clients.put("cashier", cashier);

        boolean miniEnabled = r.miniProgramPayEnabled;
        boolean miniWechat = miniEnabled && r.miniProgramWechatEnabled;
        boolean miniBalance = miniEnabled && r.miniProgramBalanceEnabled;
        Map<String, Object> miniProgram = new LinkedHashMap<>();
        miniProgram.put("enabled", r.miniProgramPayEnabled);
        Map<String, Object> configuredMiniChannels = new LinkedHashMap<>();
        configuredMiniChannels.put("wechat", r.miniProgramWechatEnabledConfigured);
        configuredMiniChannels.put("balance", r.miniProgramBalanceEnabled);
        configuredMiniChannels.put("alipay", r.miniProgramAlipayEnabled);
        miniProgram.put("channels", configuredMiniChannels);
        miniProgram.put("wechatMerchantReady", r.miniProgramWechatMerchantReady);
        if (admin) {
            miniProgram.put("effectiveEnabled", miniEnabled);
            Map<String, Object> effectiveMiniChannels = new LinkedHashMap<>();
            effectiveMiniChannels.put("wechat", miniWechat);
            effectiveMiniChannels.put("balance", miniBalance);
            effectiveMiniChannels.put("alipay", miniEnabled && r.miniProgramAlipayEnabled);
            miniProgram.put("effectiveChannels", effectiveMiniChannels);
            miniProgram.put("wechatMissingFields", r.miniProgramWechatMissingFields);
        }
        Map<String, Object> miniStates = new LinkedHashMap<>();
        miniStates.put("wechat", channelState(r.miniProgramWechatEnabledConfigured,
                r.miniProgramWechatMerchantReady, miniProgramWechatEnableHint(r)));
        miniStates.put("alipay", channelState(r.miniProgramAlipayEnabled, true, ""));
        miniStates.put("balance", channelState(r.miniProgramBalanceEnabled, true, ""));
        miniProgram.put("channelStates", miniStates);
        clients.put("miniProgram", miniProgram);
        return clients;
    }

    private static Map<String, Object> channelFlags(boolean wechat, boolean alipay,
                                                    boolean balance, boolean combined) {
        Map<String, Object> channels = new LinkedHashMap<>();
        channels.put("wechat", wechat);
        channels.put("alipay", alipay);
        channels.put("balance", balance);
        channels.put("combined", combined);
        return channels;
    }

    private static Map<String, Object> channelState(boolean enabled, boolean available, String hint) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("enabled", enabled);
        m.put("available", available);
        m.put("hint", hint);
        return m;
    }

    /** B 端：在 {@link #toPublicMap} 基础上标注是否本店自有配置、是否继承全店模板 */
    public Map<String, Object> toAdminMap(int shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentCapabilityEntity own = loadRowFromDb(sid);
        Map<String, Object> out = new LinkedHashMap<>(toPublicMap(sid));
        out.put("targetShopId", sid);
        out.put("scope", sid == PaymentConfigCache.GLOBAL_SHOP_ID ? "global" : "shop");
        out.put("hasOwnConfig", own != null);
        out.put("inheritsGlobal", sid != PaymentConfigCache.GLOBAL_SHOP_ID && own == null);
        ResolvedCapability cap = resolve(sid);
        out.put("wechatEnabledConfigured", cap.wechatEnabledConfigured);
        // D017：B 端保留全量——C 端精简掉的兼容/就绪字段在此补回（仅 /config 精简）
        out.put("miniProgramWechatMerchantReady", cap.miniProgramWechatMerchantReady);
        out.put("miniProgramWechatMissingFields", cap.miniProgramWechatMissingFields);
        out.put("canEnableMiniProgramWechatPay", cap.miniProgramWechatMerchantReady);
        out.put("canEnableCashierWechatPay", cap.wechatMerchantReady);
        out.put("wechatPayEnableHint", miniProgramWechatEnableHint(cap));
        out.put("globalOnlinePayEnabled", cap.onlinePayEnabled);
        out.put("clients", clientCapabilities(cap, true));
        return out;
    }

    public PaymentCapabilityEntity upsert(int shopId, Map<String, Object> body) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        if (body != null && Boolean.TRUE.equals(requestedChannel(body, "miniProgram", "wechat"))
                && !merchantConfigService.hasWechatMiniProgramPayReady(sid)) {
            List<String> missing = merchantConfigService.getWechatMiniProgramMissingFields(sid);
            throw new IllegalArgumentException(
                    PaymentMerchantReadiness.ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT
                            + "；缺少：" + String.join(", ", missing));
        }
        // 收银端微信开关可独立开启，不要求 default 线上商户就绪（可走线下收款 offline_collect）；
        // 线上微信支付发起时由 WechatJsapiChannel.createPrepay 兜底校验商户配置（D012）。
        PaymentCapabilityEntity row = loadRowFromDb(sid);
        if (row == null) {
            row = new PaymentCapabilityEntity();
            row.setShop_id(sid);
            applyDefaults(row);
        }
        // D015：组合支付开启校验——至少 2 个收银基础渠道（请求后状态）
        Boolean wantCombined = requestedChannel(body, "cashier", "combined");
        if (Boolean.TRUE.equals(wantCombined)) {
            Boolean reqWechat = requestedChannel(body, "cashier", "wechat");
            Boolean reqAlipay = requestedChannel(body, "cashier", "alipay");
            Boolean reqBalance = requestedChannel(body, "cashier", "balance");
            int baseCount = (reqWechat != null ? (reqWechat ? 1 : 0) : (intToBool(row.getCashier_wechat_enabled()) ? 1 : 0))
                    + (reqAlipay != null ? (reqAlipay ? 1 : 0) : (intToBool(row.getCashier_alipay_enabled()) ? 1 : 0))
                    + (reqBalance != null ? (reqBalance ? 1 : 0) : (intToBool(row.getCashier_balance_enabled()) ? 1 : 0));
            if (baseCount < 2) {
                throw new IllegalArgumentException("组合支付需至少 2 个收银基础渠道（微信/支付宝/余额）开启");
            }
        }
        if (body != null) {
            // 写入模型（D017）：仅 clients.*.enabled + channelStates.*.enabled + disabledMessage；
            // 全部旧平铺键/嵌套 channels 写入兼容移除（写入能力使用最新模型）
            applyClientSettings(row, body);
            if (body.containsKey("disabledMessage") && body.get("disabledMessage") != null) {
                String msg = body.get("disabledMessage").toString().trim();
                if (!msg.isEmpty()) {
                    row.setDisabled_message(msg);
                }
            }
        }
        if (row.getId() == null) {
            capabilityMapper.insert(row);
        } else {
            capabilityMapper.updateById(row);
        }
        configCache.putCapability(sid, row);
        return row;
    }
    private static void applyDefaults(PaymentCapabilityEntity row) {
        row.setOnline_pay_enabled(0);
        row.setWechat_enabled(0);
        row.setAlipay_enabled(0);
        row.setBalance_enabled(0);
        row.setCombined_enabled(1);
        row.setCashier_pay_enabled(1);
        row.setCashier_wechat_enabled(0);
        row.setCashier_alipay_enabled(0);
        row.setCashier_balance_enabled(0);
        row.setCashier_combined_enabled(1);
        row.setMini_program_pay_enabled(1);
        row.setMini_program_wechat_enabled(0);
        row.setMini_program_balance_enabled(0);
        row.setOffline_collect_enabled(1);
        row.setOffline_collect_channels("wechat,alipay");
        row.setDisabled_message(DEFAULT_DISABLED_MSG);
    }

    private static Integer readState(Map<String, Object> states, String key, Integer current) {
        Object raw = states.get(key);
        if (raw instanceof Map) {
            Map<String, Object> st = asMap(raw);
            if (st.containsKey("enabled")) {
                return boolToInt(parseBool(st.get("enabled"), intToBool(current)));
            }
            return current;
        }
        if (raw != null) {
            return boolToInt(parseBool(raw, intToBool(current)));
        }
        return current;
    }

    private static void applyClientSettings(PaymentCapabilityEntity row, Map<String, Object> body) {
        Map<String, Object> clients = asMap(body.get("clients"));
        applyCashierSettings(row, asMap(clients.get("cashier")));
        applyMiniProgramSettings(row, asMap(clients.get("miniProgram")));
    }

    private static void applyCashierSettings(PaymentCapabilityEntity row, Map<String, Object> terminal) {
        if (terminal.isEmpty()) {
            return;
        }
        if (terminal.containsKey("enabled")) {
            row.setCashier_pay_enabled(boolToInt(parseBool(
                    terminal.get("enabled"), intToBool(row.getCashier_pay_enabled()))));
        }
        Map<String, Object> states = asMap(terminal.get("channelStates"));
        row.setCashier_wechat_enabled(readState(states, "wechat", row.getCashier_wechat_enabled()));
        row.setCashier_alipay_enabled(readState(states, "alipay", row.getCashier_alipay_enabled()));
        row.setCashier_balance_enabled(readState(states, "balance", row.getCashier_balance_enabled()));
        row.setCashier_combined_enabled(readState(states, "combined", row.getCashier_combined_enabled()));
        // 收款码独立开关（D014）：channelStates.wechat_qr/alipay_qr；
        // 单一来源 = 收银端 cashier 列（D021：不再双写 offline_collect_channels / offline_collect_enabled）
        boolean qrTouched = states.containsKey("wechat_qr") || states.containsKey("alipay_qr");
        if (qrTouched) {
            row.setCashier_wechat_qr_enabled(readState(states, "wechat_qr", row.getCashier_wechat_qr_enabled()));
            row.setCashier_alipay_qr_enabled(readState(states, "alipay_qr", row.getCashier_alipay_qr_enabled()));
        }
    }

    private static void applyMiniProgramSettings(PaymentCapabilityEntity row, Map<String, Object> terminal) {
        if (terminal.isEmpty()) {
            return;
        }
        if (terminal.containsKey("enabled")) {
            row.setMini_program_pay_enabled(boolToInt(parseBool(
                    terminal.get("enabled"), intToBool(row.getMini_program_pay_enabled()))));
        }
        Map<String, Object> states = asMap(terminal.get("channelStates"));
        row.setMini_program_wechat_enabled(readState(states, "wechat", row.getMini_program_wechat_enabled()));
        row.setMini_program_balance_enabled(readState(states, "balance", row.getMini_program_balance_enabled()));
        // 小程序支付宝（D014）：channelStates.alipay
        row.setMini_program_alipay_enabled(readState(states, "alipay", row.getMini_program_alipay_enabled()));
    }
    private static Boolean requestedChannel(Map<String, Object> body, String terminalKey, String channelKey) {
        Map<String, Object> terminal = asMap(asMap(body.get("clients")).get(terminalKey));
        if (terminal.isEmpty()) {
            return null;
        }
        Object raw = asMap(terminal.get("channelStates")).get(channelKey);
        if (raw instanceof Map) {
            Map<String, Object> st = asMap(raw);
            if (st.containsKey("enabled")) {
                return parseBool(st.get("enabled"), false);
            }
            return null;
        }
        if (raw != null) {
            return parseBool(raw, false);
        }
        return null;
    }
    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object raw) {
        return raw instanceof Map ? (Map<String, Object>) raw : java.util.Collections.emptyMap();
    }

    private static boolean resolveBool(PaymentCapabilityEntity shop, PaymentCapabilityEntity global,
                                       java.util.function.Function<PaymentCapabilityEntity, Integer> getter,
                                       boolean defaultVal) {
        if (shop != null && getter.apply(shop) != null) {
            return intToBool(getter.apply(shop));
        }
        if (global != null && getter.apply(global) != null) {
            return intToBool(getter.apply(global));
        }
        return defaultVal;
    }

    private static Integer resolveNullable(PaymentCapabilityEntity shop, PaymentCapabilityEntity global,
                                            java.util.function.Function<PaymentCapabilityEntity, Integer> getter) {
        if (shop != null && getter.apply(shop) != null) {
            return getter.apply(shop);
        }
        if (global != null && getter.apply(global) != null) {
            return getter.apply(global);
        }
        return null;
    }

    private static String resolveString(PaymentCapabilityEntity shop, PaymentCapabilityEntity global,
                                        java.util.function.Function<PaymentCapabilityEntity, String> getter,
                                        String defaultVal) {
        if (shop != null && StringUtils.hasText(getter.apply(shop))) {
            return getter.apply(shop).trim();
        }
        if (global != null && StringUtils.hasText(getter.apply(global))) {
            return getter.apply(global).trim();
        }
        return defaultVal;
    }

    public static List<String> parseChannelList(String raw) {
        if (!StringUtils.hasText(raw)) {
            return Arrays.asList("wechat", "alipay");
        }
        return Arrays.stream(raw.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .map(String::toLowerCase)
                .distinct()
                .collect(Collectors.toList());
    }

    public static String serializeChannels(Object raw) {
        if (raw instanceof List) {
            List<String> out = new ArrayList<>();
            for (Object o : (List<?>) raw) {
                if (o != null && StringUtils.hasText(o.toString())) {
                    out.add(o.toString().trim().toLowerCase());
                }
            }
            return String.join(",", out);
        }
        if (raw != null && StringUtils.hasText(raw.toString())) {
            return serializeChannels(parseChannelList(raw.toString()));
        }
        return "wechat,alipay";
    }

    private static boolean parseBool(Object raw, boolean def) {
        if (raw == null) {
            return def;
        }
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        String s = raw.toString().trim();
        if ("1".equals(s) || "true".equalsIgnoreCase(s) || "yes".equalsIgnoreCase(s)) {
            return true;
        }
        if ("0".equals(s) || "false".equalsIgnoreCase(s) || "no".equalsIgnoreCase(s)) {
            return false;
        }
        return def;
    }

    private static int boolToInt(boolean v) {
        return v ? 1 : 0;
    }

    private static boolean intToBool(Integer v) {
        return v != null && v != 0;
    }

    public static final class ResolvedCapability {
        public int shopId;
        public boolean wechatMerchantReady;
        public boolean miniProgramWechatMerchantReady;
        public List<String> miniProgramWechatMissingFields;
        /** 能力表中配置的微信开关（未因缺商户被改写） */
        public boolean wechatEnabledConfigured;
        public boolean onlinePayEnabled;
        /** 实际生效的微信支付（须已配商户且配置为开） */
        public boolean wechatEnabled;
        public boolean alipayEnabled;
        public boolean balanceEnabled;
        public boolean combinedEnabled;
        public boolean cashierPayEnabled;
        public boolean cashierWechatEnabledConfigured;
        public boolean cashierWechatEnabled;
        public boolean cashierAlipayEnabled;
        public boolean cashierBalanceEnabled;
        public boolean cashierCombinedEnabled;
        public boolean miniProgramPayEnabled;
        public boolean miniProgramWechatEnabledConfigured;
        public boolean miniProgramWechatEnabled;
        public boolean miniProgramBalanceEnabled;
        public boolean offlineCollectEnabled;
        public List<String> offlineCollectChannels;
        public boolean cashierWechatQrEnabled;
        public boolean cashierAlipayQrEnabled;
        public boolean miniProgramAlipayEnabled;
        public boolean combinedAvailable;
        public boolean miniProgramWechatAvailable;
        public String disabledMessage;
    }
}
