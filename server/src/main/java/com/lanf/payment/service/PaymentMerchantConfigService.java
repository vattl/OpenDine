package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.payment.PaymentChannels;
import com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.config.PaymentCredentialCipher;
import com.lanf.payment.config.ResolvedWechatMerchant;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentMerchantConfigHistoryEntity;
import com.lanf.payment.mapper.PaymentMerchantConfigHistoryMapper;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import com.lanf.payment.support.PaymentMerchantFieldValidator;
import com.lanf.payment.support.PaymentMerchantReadiness;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AccessDeniedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.KeyStore;
import java.security.PublicKey;
import java.util.UUID;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class PaymentMerchantConfigService {

    private static final Logger log = LoggerFactory.getLogger(PaymentMerchantConfigService.class);

    @Autowired
    private PaymentMerchantConfigMapper merchantMapper;
    @Autowired
    private PaymentMerchantConfigHistoryMapper merchantHistoryMapper;
    @Autowired
    private PaymentMerchantPolicyService merchantPolicyService;
    @Autowired
    private PaymentConfigCache configCache;
    @Autowired
    private PaymentCredentialCipher credentialCipher;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private WechatPlatformPublicKeyLoader platformPublicKeyLoader;
    @Autowired
    private com.lanf.payment.channel.wechat.WechatMerchantKeyStore wechatMerchantKeyStore;
    @Value("${app.public-base-url:https://laofei.com.cn}")
    private String publicBaseUrl;
    @Value("${payment.private-key-upload-dir:/www/wwwroot/upload/payment-keys}")
    private String privateKeyUploadDir;

    public List<PaymentMerchantConfigEntity> listFromDb(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        QueryWrapper<PaymentMerchantConfigEntity> qw = new QueryWrapper<PaymentMerchantConfigEntity>()
                .eq("shop_id", sid);
        if (StringUtils.hasText(channel)) {
            qw.eq("channel", channel.trim().toLowerCase());
        }
        qw.orderByAsc("sort_order", "id");
        return merchantMapper.selectList(qw);
    }

    /** 运行时可参与路由的商户；默认只返回本店，显式策略开启后才补充全局模板。 */
    public List<PaymentMerchantConfigEntity> listRuntimeMerchants(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        List<PaymentMerchantConfigEntity> rows = new ArrayList<>();
        for (PaymentMerchantConfigEntity row : listFromDb(sid, channel)) if (isEnabled(row)) rows.add(row);
        if (sid > 0 && merchantPolicyService != null && merchantPolicyService.allowsGlobalFallback(sid)) {
            Set<String> ownedKeys = rows.stream().map(PaymentMerchantConfigEntity::getMerchant_key).collect(Collectors.toSet());
            for (PaymentMerchantConfigEntity row : listFromDb(PaymentConfigCache.GLOBAL_SHOP_ID, channel)) {
                if (isEnabled(row) && !ownedKeys.contains(row.getMerchant_key())) rows.add(row);
            }
        }
        return rows;
    }

    public void reloadShopChannelToCache(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = channel == null ? PaymentChannels.WECHAT : channel.trim().toLowerCase();
        configCache.putMerchants(sid, ch, listFromDb(sid, ch));
        platformPublicKeyLoader.invalidateAll();
        wechatMerchantKeyStore.invalidatePrivateKeyCache();
    }

    /**
     * 本店或全店模板是否已存在启用的 default 微信商户行（仅判断有无配置，不校验字段是否填齐）。
     */
    public boolean hasWechatPayReady(Integer shopId) {
        return findMergedRow(shopId, PaymentChannels.WECHAT, "default") != null;
    }

    /**
     * 小程序微信支付严格就绪：default 商户已启用，且 JSAPI 下单、回调验签所需字段全部存在。
     */
    public boolean hasWechatMiniProgramPayReady(Integer shopId) {
        return getWechatMiniProgramMissingFields(shopId).isEmpty();
    }

    public List<String> getWechatMiniProgramMissingFields(Integer shopId) {
        PaymentMerchantConfigEntity row =
                findMergedRow(shopId, PaymentChannels.WECHAT, "default");
        return getWechatRowMissingFields(row);
    }

    /**
     * 检查指定门店的指定渠道商户是否在 DB 存在、已启用且核心支付字段/密钥齐备（PayReady）。
     */
    public boolean isMerchantPayReady(Integer shopId, String channel, String merchantKey) {
        if (!PaymentChannels.WECHAT.equalsIgnoreCase(channel)) {
            return false;
        }
        PaymentMerchantConfigEntity row = findMergedRow(shopId, channel, normalizeMerchantKey(merchantKey));
        return row != null && isEnabled(row) && getWechatRowMissingFields(row).isEmpty();
    }

    /** 收银付款码支付完整就绪：默认商户检查。在 APIv3 基础配置之外还需要独立 APIv2 密钥和双向客户端证书。 */
    public List<String> getWechatMicropayMissingFields(Integer shopId) {
        return getWechatMicropayMissingFields(shopId, "default");
    }

    /** 按具体商户标识检查付款码支付所需凭证是否完整。 */
    public List<String> getWechatMicropayMissingFields(Integer shopId, String merchantKey) {
        PaymentMerchantConfigEntity row = findMergedRow(shopId, PaymentChannels.WECHAT, normalizeMerchantKey(merchantKey));
        List<String> missing = new ArrayList<>();
        if (row == null || !isEnabled(row)) missing.add("enabled");
        if (row == null || !StringUtils.hasText(row.getApp_id())) missing.add("appId");
        if (row == null || !StringUtils.hasText(row.getMch_id())) missing.add("mchId");
        if (row == null || !StringUtils.hasText(row.getApi_v2_key_enc())) {
            missing.add("apiV2Key");
        } else {
            try {
                String key = credentialCipher.decrypt(row.getApi_v2_key_enc());
                if (key == null || key.length() != 32) addMissingField(missing, "apiV2Key");
            } catch (RuntimeException e) {
                addMissingField(missing, "apiV2Key");
            }
        }
        if (row == null || !StringUtils.hasText(row.getClient_cert_p12_ref())
                || row.getClient_cert_p12_ref().trim().startsWith("classpath:")
                || !Files.isRegularFile(Paths.get(row.getClient_cert_p12_ref().trim()))) {
            missing.add("clientCertP12Ref");
        }
        return missing;
    }

    /**
     * 解析微信商户配置：本店启用行 → 全店模板（shop_id=0）；无则 null。
     */
    public ResolvedWechatMerchant resolveWechat(Integer shopId, String merchantKey) {
        PaymentMerchantConfigEntity row = findMergedRow(shopId, PaymentChannels.WECHAT, normalizeMerchantKey(merchantKey));
        if (row == null || !isEnabled(row)) {
            return null;
        }
        return toResolved(row);
    }

    /** 按交易固化的配置 ID/版本解析；当前行升级后回读历史快照。 */
    public ResolvedWechatMerchant resolveWechatBound(Long configId, Integer version) {
        if (configId == null || version == null || version <= 0) return null;
        PaymentMerchantConfigEntity current = merchantMapper.selectById(configId);
        if (current != null && version.equals(currentVersion(current))) return toResolved(current);
        PaymentMerchantConfigHistoryEntity history = merchantHistoryMapper.selectOne(
                new QueryWrapper<PaymentMerchantConfigHistoryEntity>()
                        .eq("merchant_config_id", configId)
                        .eq("credential_version", version)
                        .last("LIMIT 1"));
        return history == null ? null : toResolved(history);
    }

    /**
     * 支付回调：按 {@code Wechatpay-Serial} 在 DB 启用行中匹配验签与解密候选。
     */
    public List<NotifyCryptoMatch> findNotifyCryptoMatches(String platformPubKeyId) {
        if (!StringUtils.hasText(platformPubKeyId)) {
            return new ArrayList<>();
        }
        String serial = platformPubKeyId.trim();
        List<NotifyCryptoMatch> out = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        List<PaymentMerchantConfigEntity> rows = merchantMapper.selectList(
                new QueryWrapper<PaymentMerchantConfigEntity>()
                        .eq("channel", PaymentChannels.WECHAT)
                        .eq("platform_pub_key_id", serial));
        if (rows != null) {
            for (PaymentMerchantConfigEntity row : rows) {
                ResolvedWechatMerchant merged = toResolved(row);
                if (!StringUtils.hasText(merged.platformPubKeyRef) || !StringUtils.hasText(merged.apiV3Key)) continue;
                if (!serial.equals(merged.platformPubKeyId)) {
                    continue;
                }
                String dedupe = row.getShop_id() + ":" + merged.merchantKey + ":" + merged.apiV3Key;
                if (!seen.add(dedupe)) {
                    continue;
                }
                NotifyCryptoMatch m = new NotifyCryptoMatch();
                m.configId = row.getId();
                m.configVersion = currentVersion(row);
                m.shopId = row.getShop_id();
                m.merchantKey = merged.merchantKey;
                m.legacyMerchantId = merged.legacyMerchantId;
                m.mchId = merged.mchId;
                m.appId = merged.appId;
                m.platformPubKeyRef = merged.platformPubKeyRef;
                m.apiV3Key = merged.apiV3Key;
                out.add(m);
            }
        }
        List<PaymentMerchantConfigHistoryEntity> historyRows = merchantHistoryMapper.selectList(
                new QueryWrapper<PaymentMerchantConfigHistoryEntity>()
                        .eq("channel", PaymentChannels.WECHAT)
                        .eq("platform_pub_key_id", serial));
        if (historyRows != null) {
            for (PaymentMerchantConfigHistoryEntity row : historyRows) {
                ResolvedWechatMerchant merged = toResolved(row);
                if (!serial.equals(merged.platformPubKeyId)) continue;
                String dedupe = row.getShop_id() + ":" + merged.merchantKey + ":" + merged.apiV3Key;
                if (!seen.add(dedupe)) continue;
                NotifyCryptoMatch m = new NotifyCryptoMatch();
                m.configId = row.getMerchant_config_id(); m.configVersion = row.getCredential_version();
                m.shopId = row.getShop_id(); m.merchantKey = merged.merchantKey;
                m.legacyMerchantId = merged.legacyMerchantId; m.platformPubKeyRef = merged.platformPubKeyRef;
                m.apiV3Key = merged.apiV3Key; m.mchId = merged.mchId; m.appId = merged.appId; out.add(m);
            }
        }
        return out;
    }

    private ResolvedWechatMerchant toResolved(PaymentMerchantConfigEntity row) {
        String mk = normalizeMerchantKey(row.getMerchant_key());
        ResolvedWechatMerchant r = new ResolvedWechatMerchant();
        r.merchantKey = mk;
        r.legacyMerchantId = "small_amount".equals(mk) ? "2" : "1";
        r.dbConfigId = row.getId();
        r.dbShopId = row.getShop_id();
        r.dbCredentialVersion = currentVersion(row);
        r.appId = trimToEmpty(row.getApp_id());
        r.mchId = trimToEmpty(row.getMch_id());
        r.notifyUrl = trimToEmpty(row.getNotify_url());
        r.refundNotifyUrl = trimToEmpty(row.getRefund_notify_url());
        r.serialNo = trimToEmpty(row.getSerial_no());
        r.platformPubKeyId = trimToEmpty(row.getPlatform_pub_key_id());
        r.platformPubKeyRef = trimToEmpty(row.getPlatform_pub_key_ref());
        r.privateKeyRef = trimToEmpty(row.getPrivate_key_ref());
        r.clientCertP12Ref = trimToEmpty(row.getClient_cert_p12_ref());
        if (StringUtils.hasText(row.getApi_v3_key_enc())) {
            r.apiV3Key = credentialCipher.decrypt(row.getApi_v3_key_enc());
        }
        if (StringUtils.hasText(row.getApi_v2_key_enc())) {
            r.apiV2Key = credentialCipher.decrypt(row.getApi_v2_key_enc());
        }
        return r;
    }

    private ResolvedWechatMerchant toResolved(PaymentMerchantConfigHistoryEntity row) {
        PaymentMerchantConfigEntity current = new PaymentMerchantConfigEntity();
        current.setId(row.getMerchant_config_id()); current.setShop_id(row.getShop_id());
        current.setChannel(row.getChannel()); current.setMerchant_key(row.getMerchant_key());
        current.setCredential_version(row.getCredential_version()); current.setEnabled(1); current.setStatus("ACTIVE");
        current.setApp_id(row.getApp_id()); current.setMch_id(row.getMch_id());
        current.setNotify_url(row.getNotify_url()); current.setRefund_notify_url(row.getRefund_notify_url());
        current.setApi_v3_key_enc(row.getApi_v3_key_enc()); current.setApi_v2_key_enc(row.getApi_v2_key_enc());
        current.setSerial_no(row.getSerial_no()); current.setPlatform_pub_key_id(row.getPlatform_pub_key_id());
        current.setPlatform_pub_key_ref(row.getPlatform_pub_key_ref()); current.setPrivate_key_ref(row.getPrivate_key_ref());
        current.setClient_cert_p12_ref(row.getClient_cert_p12_ref());
        return toResolved(current);
    }

    private static String trimToEmpty(String s) {
        return s == null ? "" : s.trim();
    }

    public static final class NotifyCryptoMatch {
        public Long configId;
        public Integer configVersion;
        public Integer shopId;
        public String merchantKey;
        public String legacyMerchantId;
        public String mchId;
        public String appId;
        public String platformPubKeyRef;
        public String apiV3Key;
    }

    public PaymentMerchantConfigEntity findMergedRow(Integer shopId, String channel, String merchantKey) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = channel.trim().toLowerCase();
        String mk = normalizeMerchantKey(merchantKey);
        PaymentMerchantConfigEntity shop = findInCacheOrDb(sid, ch, mk);
        if (shop != null) {
            return shop;
        }
        if (sid != PaymentConfigCache.GLOBAL_SHOP_ID && merchantPolicyService != null
                && merchantPolicyService.allowsGlobalFallback(sid)) {
            return findInCacheOrDb(PaymentConfigCache.GLOBAL_SHOP_ID, ch, mk);
        }
        return null;
    }

    private PaymentMerchantConfigEntity findInCacheOrDb(int shopId, String channel, String merchantKey) {
        // 资金路由以数据库为权威。JVM 本地缓存没有跨实例失效能力，不能用于决定新交易收款商户。
        List<PaymentMerchantConfigEntity> db = listFromDb(shopId, channel);
        configCache.putMerchants(shopId, channel, db);
        for (PaymentMerchantConfigEntity e : db) {
            if (merchantKey.equals(e.getMerchant_key()) && isEnabled(e)) {
                return e;
            }
        }
        return null;
    }

    public PaymentMerchantConfigEntity getById(long id) {
        return merchantMapper.selectById(id);
    }

    public List<Map<String, Object>> listPublic(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        List<PaymentMerchantConfigEntity> rows = listFromDb(sid, channel);
        if (rows.isEmpty() && sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            rows = listFromDb(PaymentConfigCache.GLOBAL_SHOP_ID, channel);
        }
        return rows.stream().map(this::toPublicMap).collect(Collectors.toList());
    }

    /**
     * B 端列表：本店配置与全店模板分开展示，避免门店误改继承项。
     */
    public Map<String, Object> listForAdmin(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("targetShopId", sid);
        out.put("scope", sid == PaymentConfigCache.GLOBAL_SHOP_ID ? "global" : "shop");
        out.put("channel", StringUtils.hasText(channel) ? channel.trim().toLowerCase() : PaymentChannels.WECHAT);
        List<Map<String, Object>> owned = listFromDb(sid, channel).stream()
                .map(row -> {
                    Map<String, Object> m = toAdminEditMap(row);
                    m.put("editable", true);
                    return m;
                })
                .collect(Collectors.toList());
        out.put("owned", owned);
        if (sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            List<Map<String, Object>> inherited = listFromDb(PaymentConfigCache.GLOBAL_SHOP_ID, channel).stream()
                    .map(row -> {
                        Map<String, Object> m = toPublicMap(row);
                        m.put("inherited", true);
                        m.put("readOnly", true);
                        return m;
                    })
                    .collect(Collectors.toList());
            out.put("inheritedTemplates", inherited);
        } else {
            out.put("inheritedTemplates", new ArrayList<>());
        }
        return out;
    }

    public Map<String, Object> toPublicMap(PaymentMerchantConfigEntity row) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", row.getId());
        m.put("shopId", row.getShop_id());
        m.put("channel", row.getChannel());
        m.put("merchantKey", row.getMerchant_key());
        m.put("enabled", isEnabled(row));
        m.put("status", normalizedStatus(row));
        m.put("credentialVersion", currentVersion(row));
        m.put("appId", row.getApp_id());
        m.put("mchId", row.getMch_id());
        m.put("notifyUrl", row.getNotify_url());
        m.put("refundNotifyUrl", row.getRefund_notify_url());
        m.put("apiV3KeyMasked", PaymentCredentialCipher.maskSecret(
                StringUtils.hasText(row.getApi_v3_key_enc()) ? "enc" : ""));
        m.put("apiV2KeyMasked", PaymentCredentialCipher.maskSecret(
                StringUtils.hasText(row.getApi_v2_key_enc()) ? "enc" : ""));
        m.put("serialNo", row.getSerial_no());
        m.put("platformPubKeyId", row.getPlatform_pub_key_id());
        m.put("platformPubKeyRefMasked", maskRef(row.getPlatform_pub_key_ref()));
        m.put("privateKeyRefMasked", maskRef(row.getPrivate_key_ref()));
        m.put("clientCertP12RefMasked", maskRef(row.getClient_cert_p12_ref()));
        m.put("alipayAppCertRefMasked", maskRef(row.getAlipay_app_cert_ref()));
        m.put("alipayPublicCertRefMasked", maskRef(row.getAlipay_public_cert_ref()));
        m.put("alipayRootCertRefMasked", maskRef(row.getAlipay_root_cert_ref()));
        m.put("routingRuleJson", row.getRouting_rule_json());
        m.put("sortOrder", row.getSort_order());
        m.put("remark", row.getRemark());
        List<String> missingFields = PaymentChannels.WECHAT.equalsIgnoreCase(row.getChannel())
                && "default".equals(normalizeMerchantKey(row.getMerchant_key()))
                ? getWechatRowMissingFields(row)
                : new ArrayList<>();
        m.put("payReady", missingFields.isEmpty() && isEnabled(row));
        m.put("missingFields", missingFields);
        return m;
    }

    /**
     * B 端编辑表单：返回可回填字段（路径类字段对 classpath 不脱敏；密钥仅 has* 标记）。
     */
    public Map<String, Object> toAdminEditMap(PaymentMerchantConfigEntity row) {
        Map<String, Object> m = new LinkedHashMap<>(toPublicMap(row));
        m.put("exists", true);
        m.put("editable", true);
        m.put("hasApiV3Key", StringUtils.hasText(row.getApi_v3_key_enc()));
        m.put("apiV3Key", StringUtils.hasText(row.getApi_v3_key_enc()) ? "******" : "");
        m.put("hasApiV2Key", StringUtils.hasText(row.getApi_v2_key_enc()));
        m.put("apiV2Key", StringUtils.hasText(row.getApi_v2_key_enc()) ? "******" : "");
        m.put("hasPrivateKey", StringUtils.hasText(row.getPrivate_key_ref()));
        m.put("privateKeyRef", revealRefForEdit(row.getPrivate_key_ref()));
        m.put("hasClientCertP12", StringUtils.hasText(row.getClient_cert_p12_ref()));
        m.put("clientCertP12Ref", revealRefForEdit(row.getClient_cert_p12_ref()));
        m.put("platformPubKeyRef", revealRefForEdit(row.getPlatform_pub_key_ref()));
        m.put("hasAlipayAppCert", StringUtils.hasText(row.getAlipay_app_cert_ref()));
        m.put("alipayAppCertRef", revealRefForEdit(row.getAlipay_app_cert_ref()));
        m.put("hasAlipayPublicCert", StringUtils.hasText(row.getAlipay_public_cert_ref()));
        m.put("alipayPublicCertRef", revealRefForEdit(row.getAlipay_public_cert_ref()));
        m.put("hasAlipayRootCert", StringUtils.hasText(row.getAlipay_root_cert_ref()));
        m.put("alipayRootCertRef", revealRefForEdit(row.getAlipay_root_cert_ref()));
        m.put("notifyUrlSuggestions", notifyUrlTemplates());
        m.put("updatedAt", row.getUpdated_at());
        m.put("createdAt", row.getCreated_at());
        return m;
    }

    /**
     * 按门店 + 渠道 + merchantKey 拉取本店配置（含已禁用行），用于编辑页。
     */
    public PaymentMerchantConfigEntity findOwnedRowByKey(int shopId, String channel, String merchantKey) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = StringUtils.hasText(channel) ? channel.trim().toLowerCase() : PaymentChannels.WECHAT;
        String mk = normalizeMerchantKey(merchantKey);
        return merchantMapper.selectOne(new QueryWrapper<PaymentMerchantConfigEntity>()
                .eq("shop_id", sid)
                .eq("channel", ch)
                .eq("merchant_key", mk)
                .last("LIMIT 1"));
    }

    /**
     * 编辑表单：有则返回已有行，无则返回空白模板（含推荐回调 URL）。
     */
    public Map<String, Object> getAdminEditForm(int shopId, String channel, String merchantKey) {
        PaymentMerchantConfigEntity row = findOwnedRowByKey(shopId, channel, merchantKey);
        if (row != null) {
            return toAdminEditMap(row);
        }
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = StringUtils.hasText(channel) ? channel.trim().toLowerCase() : PaymentChannels.WECHAT;
        String mk = normalizeMerchantKey(merchantKey);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", null);
        m.put("exists", false);
        m.put("editable", true);
        m.put("shopId", sid);
        m.put("channel", ch);
        m.put("merchantKey", mk);
        m.put("enabled", true);
        m.put("appId", "");
        m.put("mchId", "");
        Map<String, String> notifyTpl = notifyUrlTemplates();
        m.put("notifyUrl", notifyTpl.getOrDefault("wechatPayNotify", ""));
        m.put("refundNotifyUrl", notifyTpl.getOrDefault("wechatRefundNotify", ""));
        m.put("notifyUrlSuggestions", notifyTpl);
        m.put("hasApiV3Key", false);
        m.put("apiV3Key", "");
        m.put("hasApiV2Key", false);
        m.put("apiV2Key", "");
        m.put("serialNo", "");
        m.put("platformPubKeyId", "");
        m.put("platformPubKeyRef", "");
        m.put("hasPrivateKey", false);
        m.put("privateKeyRef", "");
        m.put("hasClientCertP12", false);
        m.put("clientCertP12Ref", "");
        m.put("hasAlipayAppCert", false);
        m.put("alipayAppCertRef", "");
        m.put("hasAlipayPublicCert", false);
        m.put("alipayPublicCertRef", "");
        m.put("hasAlipayRootCert", false);
        m.put("alipayRootCertRef", "");
        m.put("routingRuleJson", null);
        m.put("sortOrder", 10);
        m.put("remark", "");
        m.put("payReady", false);
        m.put("missingFields", PaymentMerchantReadiness.missingFields(null));
        return m;
    }

    /**
     * 保存或更新本店商户：body 带 {@code id} 则按 id 更新；否则按 channel+merchantKey 查找本店行，有则更新、无则新建。
     */
    public PaymentMerchantConfigEntity saveOrUpdate(int shopId, Map<String, Object> body) {
        if (body == null) {
            throw new IllegalArgumentException("请求体不能为空");
        }
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        Long id = parseLongId(body.get("id"));
        if (id != null && id > 0) {
            return save(sid, id, body);
        }
        String ch = str(firstPresent(body, "channel"));
        if (!StringUtils.hasText(ch)) {
            ch = PaymentChannels.WECHAT;
        }
        String mk = normalizeMerchantKey(str(firstPresent(body, "merchantKey", "merchant_key")));
        PaymentMerchantConfigEntity existing = findOwnedRowByKey(sid, ch, mk);
        if (existing != null) {
            return save(sid, existing.getId(), body);
        }
        return save(sid, null, body);
    }

    @Transactional
    public PaymentMerchantConfigEntity save(int shopId, Long id, Map<String, Object> body) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentMerchantConfigEntity row;
        if (id != null && id > 0) {
            row = merchantMapper.selectById(id);
            if (row == null || row.getShop_id() != sid) {
                throw new IllegalArgumentException("商户配置不存在");
            }
        } else {
            row = new PaymentMerchantConfigEntity();
            row.setShop_id(sid);
            row.setEnabled(1);
            row.setStatus("ACTIVE");
            row.setCredential_version(1);
        }
        PaymentMerchantConfigEntity previous = row.getId() == null ? null : copy(row);
        applyBody(row, body, id == null);
        if (previous != null && (!java.util.Objects.equals(previous.getChannel(), row.getChannel())
                || !java.util.Objects.equals(previous.getMerchant_key(), row.getMerchant_key()))) {
            throw new IllegalArgumentException("已存在商户的 channel/merchantKey 不可修改，请新建商户配置");
        }
        if (previous != null && "RETIRED".equalsIgnoreCase(previous.getStatus())) {
            row.setStatus("RETIRED");
            row.setEnabled(0);
        }
        if (PaymentChannels.WECHAT.equalsIgnoreCase(row.getChannel())) {
            if (!StringUtils.hasText(row.getNotify_url())) {
                row.setNotify_url(defaultWechatPayNotifyUrl());
            }
            if (!StringUtils.hasText(row.getRefund_notify_url())) {
                row.setRefund_notify_url(defaultWechatRefundNotifyUrl());
            }
        }
        if (row.getId() == null) {
            merchantMapper.insert(row);
        } else {
            snapshot(previous);
            row.setCredential_version(currentVersion(previous) + 1);
            merchantMapper.updateById(row);
        }
        reloadShopChannelToCache(sid, row.getChannel());
        return row;
    }

    /**
     * 保存前端上传的商户 PEM 私钥到服务器文件系统，返回可写入 DB 的路径引用。
     * 返回值为普通文件路径（支持 {@link com.lanf.payment.channel.wechat.WechatMerchantKeyStore} 读取），不是 PEM 内容。
     */
    public String storePrivateKeyPem(int shopId, String merchantKey, MultipartFile file) throws IOException {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String mk = normalizeMerchantKey(merchantKey);
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("请上传 PEM 私钥文件");
        }
        if (file.getSize() > 64 * 1024) {
            throw new IllegalArgumentException("PEM 私钥文件过大（最多 64KB）");
        }
        String pem = new String(file.getBytes(), StandardCharsets.UTF_8).trim();
        validatePrivateKeyPem(pem);

        Path base = resolvePrivateKeyUploadDir();
        Path dir = base.resolve("shop-" + sid);
        try {
            Files.createDirectories(dir);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(dir, "无法创建门店子目录", e), e);
        }
        // 文件名不可覆盖旧版本；历史交易必须仍能读取创建时绑定的私钥。
        Path target = dir.resolve("wechat-" + sanitizeFilePart(mk) + "-"
                + UUID.randomUUID().toString().replace("-", "") + "-private-key.pem");
        try {
            Files.write(target, (pem + System.lineSeparator()).getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(target, "无法写入私钥文件", e), e);
        }
        restrictOwnerRead(target);
        return normalizePathRef(target);
    }

    /**
     * 保存微信支付平台公钥或 X.509 平台证书，数据库仅记录返回的文件路径。
     */
    public PlatformPublicMaterial storePlatformPublicKeyPem(
            int shopId, String merchantKey, MultipartFile file) throws IOException {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String mk = normalizeMerchantKey(merchantKey);
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("请上传微信支付平台公钥或平台证书文件");
        }
        if (file.getSize() > 64 * 1024) {
            throw new IllegalArgumentException("公钥证书文件过大（最多 64KB）");
        }
        String pem = new String(file.getBytes(), StandardCharsets.UTF_8).trim();
        if (pem.contains("-----BEGIN PRIVATE KEY-----")
                || pem.contains("-----BEGIN RSA PRIVATE KEY-----")) {
            throw new IllegalArgumentException("请上传微信支付平台公钥或平台证书，不要上传私钥文件");
        }
        String materialType;
        if (pem.contains("-----BEGIN PUBLIC KEY-----") && pem.contains("-----END PUBLIC KEY-----")) {
            materialType = "PUBLIC_KEY";
        } else if (pem.contains("-----BEGIN CERTIFICATE-----") && pem.contains("-----END CERTIFICATE-----")) {
            materialType = "CERTIFICATE";
        } else {
            throw new IllegalArgumentException("文件不是有效的微信支付平台公钥或 X.509 平台证书");
        }
        try {
            PublicKey publicKey = WechatPlatformPublicKeyLoader.parsePemPublicKey(pem);
            if (!"RSA".equalsIgnoreCase(publicKey.getAlgorithm())) {
                throw new IllegalArgumentException("微信支付平台公钥必须为 RSA 公钥");
            }
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("无法解析微信支付平台公钥证书：" + e.getMessage(), e);
        }

        Path base = resolvePrivateKeyUploadDir();
        Path dir = base.resolve("shop-" + sid);
        try {
            Files.createDirectories(dir);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(dir, "无法创建门店子目录", e), e);
        }
        Path target = dir.resolve("wechat-" + sanitizeFilePart(mk) + "-"
                + UUID.randomUUID().toString().replace("-", "") + "-platform-public.pem");
        try {
            Files.write(target, (pem + System.lineSeparator()).getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(target, "无法写入公钥证书文件", e), e);
        }
        restrictOwnerRead(target);
        return new PlatformPublicMaterial(normalizePathRef(target), materialType);
    }

    public static final class PlatformPublicMaterial {
        public final String platformPubKeyRef;
        public final String materialType;

        public PlatformPublicMaterial(String platformPubKeyRef, String materialType) {
            this.platformPubKeyRef = platformPubKeyRef;
            this.materialType = materialType;
        }
    }

    @Transactional
    public PaymentMerchantConfigEntity uploadPrivateKeyForMerchant(PaymentMerchantConfigEntity row, MultipartFile file) throws IOException {
        if (row == null) {
            throw new IllegalArgumentException("商户配置不存在");
        }
        String ref = storePrivateKeyPem(row.getShop_id(), row.getMerchant_key(), file);
        PaymentMerchantConfigEntity previous = copy(row);
        row.setPrivate_key_ref(PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref));
        snapshot(previous);
        row.setCredential_version(currentVersion(previous) + 1);
        merchantMapper.updateById(row);
        reloadShopChannelToCache(row.getShop_id(), row.getChannel());
        return row;
    }

    /**
     * 保存前端上传的商户客户端 PKCS12 证书（.p12 / .pfx）到服务器文件系统，返回可写入 DB 的路径引用。
     */
    public String storeClientCertP12(int shopId, String merchantKey, MultipartFile file) throws IOException {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String mk = normalizeMerchantKey(merchantKey);
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("请上传客户端双向认证证书（.p12/.pfx）文件");
        }
        if (file.getSize() > 512 * 1024) {
            throw new IllegalArgumentException("客户端证书文件过大（最多 512KB）");
        }
        byte[] bytes = file.getBytes();
        validateClientCertP12(bytes);

        Path base = resolvePrivateKeyUploadDir();
        Path dir = base.resolve("shop-" + sid);
        try {
            Files.createDirectories(dir);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(dir, "无法创建门店子目录", e), e);
        }
        Path target = dir.resolve("wechat-" + sanitizeFilePart(mk) + "-"
                + UUID.randomUUID().toString().replace("-", "") + "-apiclient-cert.p12");
        try {
            Files.write(target, bytes,
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(target, "无法写入客户端证书文件", e), e);
        }
        restrictOwnerRead(target);
        return normalizePathRef(target);
    }

    private void validateClientCertP12(byte[] bytes) {
        if (bytes == null || bytes.length < 24) {
            throw new IllegalArgumentException("证书内容过短或损坏");
        }
        String head = new String(bytes, 0, Math.min(bytes.length, 64), StandardCharsets.ISO_8859_1);
        if (head.startsWith("-") || head.contains("-----BEGIN")) {
            throw new IllegalArgumentException("上传的是 PEM 文本文件，客户端证书必须为 PKCS12 二进制（.p12/.pfx）文件");
        }
        try {
            KeyStore ks = KeyStore.getInstance("PKCS12");
            ks.load(new ByteArrayInputStream(bytes), new char[0]);
        } catch (IOException e) {
            String msg = e.getMessage() != null ? e.getMessage().toLowerCase() : "";
            Throwable cause = e.getCause();
            boolean isPasswordOrIntegrityError = msg.contains("password") || msg.contains("mac") || msg.contains("decrypt")
                    || msg.contains("wrong key") || msg.contains("bad padding")
                    || msg.contains("failed to decrypt") || msg.contains("keystore password")
                    || msg.contains("integrity") || msg.contains("unrecoverable")
                    || (cause instanceof java.security.UnrecoverableKeyException)
                    || (cause instanceof java.security.GeneralSecurityException);
            if (isPasswordOrIntegrityError) {
                // 有密码保护的正常 PKCS12 容器（由于未传或密码不匹配而报 MAC/Integrity/密码校验失败）
            } else {
                throw new IllegalArgumentException("文件不是合法的 PKCS12（.p12/.pfx）证书格式：" + e.getMessage(), e);
            }
        } catch (Exception e) {
            throw new IllegalArgumentException("无法校验客户端证书格式：" + e.getMessage(), e);
        }
    }

    /**
     * 保存支付宝公钥/根/应用证书（.crt/.pem），返回落盘路径。
     */
    public String storeAlipayCert(int shopId, String merchantKey, String certSubtype, MultipartFile file) throws IOException {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String mk = normalizeMerchantKey(merchantKey);
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("请上传支付宝证书文件");
        }
        if (file.getSize() > 64 * 1024) {
            throw new IllegalArgumentException("证书文件过大（最多 64KB）");
        }
        byte[] bytes = file.getBytes();
        String text = new String(bytes, StandardCharsets.UTF_8).trim();
        if (!text.contains("-----BEGIN CERTIFICATE-----") || !text.contains("-----END CERTIFICATE-----")) {
            throw new IllegalArgumentException("支付宝证书必须为 X.509 PEM 证书格式（包含 -----BEGIN CERTIFICATE-----）");
        }
        Path base = resolvePrivateKeyUploadDir();
        Path dir = base.resolve("shop-" + sid);
        try {
            Files.createDirectories(dir);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(dir, "无法创建门店子目录", e), e);
        }
        String typePart = sanitizeFilePart(certSubtype != null ? certSubtype.toLowerCase() : "cert");
        Path target = dir.resolve("alipay-" + sanitizeFilePart(mk) + "-"
                + UUID.randomUUID().toString().replace("-", "") + "-" + typePart + ".crt");
        try {
            Files.write(target, (text + System.lineSeparator()).getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(target, "无法写入支付宝证书文件", e), e);
        }
        restrictOwnerRead(target);
        return normalizePathRef(target);
    }

    /**
     * 智能识别证书类型。
     */
    public String detectCertificateType(MultipartFile file, byte[] bytes) {
        String filename = file != null && file.getOriginalFilename() != null ? file.getOriginalFilename().toLowerCase() : "";
        if (filename.endsWith(".p12") || filename.endsWith(".pfx")) {
            return "CLIENT_CERT_P12";
        }
        if (bytes != null && bytes.length > 0) {
            String snippet = new String(bytes, 0, Math.min(bytes.length, 512), StandardCharsets.UTF_8).trim();
            if (snippet.contains("-----BEGIN PRIVATE KEY-----") || snippet.contains("-----BEGIN RSA PRIVATE KEY-----")) {
                return "PRIVATE_KEY";
            }
            if (snippet.contains("-----BEGIN PUBLIC KEY-----")) {
                return "PLATFORM_PUBLIC_KEY";
            }
            if (snippet.contains("-----BEGIN CERTIFICATE-----")) {
                if (filename.contains("root") || filename.contains("alipayroot")) {
                    return "ALIPAY_ROOT_CERT";
                }
                if (filename.contains("appcert") || filename.contains("app_cert")) {
                    return "ALIPAY_APP_CERT";
                }
                if (filename.contains("alipaycert") || filename.contains("alipaypublic")) {
                    return "ALIPAY_PUBLIC_CERT";
                }
                return "PLATFORM_PUBLIC_KEY";
            }
            if (bytes[0] == 0x30) {
                return "CLIENT_CERT_P12";
            }
        }
        throw new IllegalArgumentException("无法自动识别证书类型，请显式指定 type 参数（如 CLIENT_CERT_P12, PRIVATE_KEY, PLATFORM_PUBLIC_KEY）");
    }

    public static String normalizeCertificateType(String type) {
        if (!StringUtils.hasText(type)) {
            return "AUTO";
        }
        String t = type.trim().toUpperCase().replace("-", "_");
        if ("PRIVATE_KEY".equals(t) || "PRIVATE_KEY_PEM".equals(t) || "WECHAT_PRIVATE_KEY".equals(t)
                || "KEY_PEM".equals(t) || "PRIVATE_KEY_REF".equals(t)) {
            return "PRIVATE_KEY";
        }
        if ("PLATFORM_PUBLIC_KEY".equals(t) || "PLATFORM_PUB_KEY".equals(t) || "PLATFORM_CERT".equals(t)
                || "WECHAT_PLATFORM_KEY".equals(t) || "PLATFORM_PUBLIC_KEY_REF".equals(t) || "PLATFORM_PUB_KEY_REF".equals(t)) {
            return "PLATFORM_PUBLIC_KEY";
        }
        if ("CLIENT_CERT_P12".equals(t) || "PKCS12".equals(t) || "CLIENT_CERT".equals(t)
                || "WECHAT_CLIENT_CERT".equals(t) || "CLIENT_CERT_P12_REF".equals(t)) {
            return "CLIENT_CERT_P12";
        }
        if ("ALIPAY_ROOT_CERT".equals(t) || "ALIPAY_ROOT_CERT_REF".equals(t)) {
            return "ALIPAY_ROOT_CERT";
        }
        if ("ALIPAY_APP_CERT".equals(t) || "ALIPAY_APP_CERT_REF".equals(t)) {
            return "ALIPAY_APP_CERT";
        }
        if ("ALIPAY_PUBLIC_CERT".equals(t) || "ALIPAY_PUBLIC_CERT_REF".equals(t)) {
            return "ALIPAY_PUBLIC_CERT";
        }
        return t;
    }

    /**
     * 统一证书/私钥/公钥存储门面。
     */
    public UnifiedCertificateResult storeCertificateMaterial(
            int shopId, String merchantKey, String certificateType, MultipartFile file) throws IOException {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("上传的证书或密钥文件不能为空");
        }
        byte[] bytes = file.getBytes();
        String resolvedType;
        if (!StringUtils.hasText(certificateType) || "AUTO".equalsIgnoreCase(certificateType.trim())) {
            resolvedType = detectCertificateType(file, bytes);
        } else {
            resolvedType = normalizeCertificateType(certificateType);
        }

        String fileRef;
        String materialType = null;
        switch (resolvedType) {
            case "CLIENT_CERT_P12":
                fileRef = storeClientCertP12(shopId, merchantKey, file);
                break;
            case "PRIVATE_KEY":
                fileRef = storePrivateKeyPem(shopId, merchantKey, file);
                break;
            case "PLATFORM_PUBLIC_KEY":
                PlatformPublicMaterial mat = storePlatformPublicKeyPem(shopId, merchantKey, file);
                fileRef = mat.platformPubKeyRef;
                materialType = mat.materialType;
                break;
            case "ALIPAY_ROOT_CERT":
                fileRef = storeAlipayCert(shopId, merchantKey, "root-cert", file);
                break;
            case "ALIPAY_APP_CERT":
                fileRef = storeAlipayCert(shopId, merchantKey, "app-cert", file);
                break;
            case "ALIPAY_PUBLIC_CERT":
                fileRef = storeAlipayCert(shopId, merchantKey, "public-cert", file);
                break;
            default:
                throw new IllegalArgumentException("不支持的证书类型：" + certificateType);
        }
        return new UnifiedCertificateResult(
                resolvedType,
                fileRef,
                file.getOriginalFilename(),
                file.getSize(),
                materialType
        );
    }

    /**
     * 商户直绑证书上传：保存凭证文件、绑定至对应商户配置字段并递增凭据版本。
     */
    @Transactional
    public CertificateBindResult uploadCertificateForMerchant(
            PaymentMerchantConfigEntity row, String certificateType, MultipartFile file) throws IOException {
        if (row == null) {
            throw new IllegalArgumentException("商户配置不存在");
        }
        UnifiedCertificateResult stored = storeCertificateMaterial(row.getShop_id(), row.getMerchant_key(), certificateType, file);
        PaymentMerchantConfigEntity previous = copy(row);
        applyCertificateRef(row, stored.getCertificateType(), stored.getFileRef());
        snapshot(previous);
        row.setCredential_version(currentVersion(previous) + 1);
        merchantMapper.updateById(row);
        reloadShopChannelToCache(row.getShop_id(), row.getChannel());
        return new CertificateBindResult(row, stored);
    }

    private void applyCertificateRef(PaymentMerchantConfigEntity row, String certificateType, String ref) {
        String normalizedRef = PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref);
        switch (certificateType) {
            case "CLIENT_CERT_P12":
                row.setClient_cert_p12_ref(normalizedRef);
                break;
            case "PRIVATE_KEY":
                row.setPrivate_key_ref(normalizedRef);
                break;
            case "PLATFORM_PUBLIC_KEY":
                row.setPlatform_pub_key_ref(normalizedRef);
                break;
            case "ALIPAY_ROOT_CERT":
                row.setAlipay_root_cert_ref(normalizedRef);
                break;
            case "ALIPAY_APP_CERT":
                row.setAlipay_app_cert_ref(normalizedRef);
                break;
            case "ALIPAY_PUBLIC_CERT":
                row.setAlipay_public_cert_ref(normalizedRef);
                break;
            default:
                throw new IllegalArgumentException("未知的证书类型：" + certificateType);
        }
    }

    public static final class UnifiedCertificateResult {
        private final String certificateType;
        private final String fileRef;
        private final String originalFilename;
        private final long fileSize;
        private final String materialType;

        public UnifiedCertificateResult(String certificateType, String fileRef, String originalFilename, long fileSize, String materialType) {
            this.certificateType = certificateType;
            this.fileRef = fileRef;
            this.originalFilename = originalFilename;
            this.fileSize = fileSize;
            this.materialType = materialType;
        }

        public String getCertificateType() { return certificateType; }
        public String getFileRef() { return fileRef; }
        public String getOriginalFilename() { return originalFilename; }
        public long getFileSize() { return fileSize; }
        public String getMaterialType() { return materialType; }
    }

    public static final class CertificateBindResult {
        public final PaymentMerchantConfigEntity row;
        public final UnifiedCertificateResult certificateResult;

        public CertificateBindResult(PaymentMerchantConfigEntity row, UnifiedCertificateResult certificateResult) {
            this.row = row;
            this.certificateResult = certificateResult;
        }
    }

    @Transactional
    public void delete(long id, int shopId) {
        PaymentMerchantConfigEntity row = merchantMapper.selectById(id);
        int targetShopId = PaymentConfigCache.normalizeShopId(shopId);
        int rowShopId = row == null || row.getShop_id() == null
                ? PaymentConfigCache.GLOBAL_SHOP_ID : row.getShop_id();
        if (row == null || rowShopId != targetShopId) {
            throw new IllegalArgumentException("商户配置不存在");
        }
        row.setStatus("RETIRED");
        row.setEnabled(0);
        if (merchantMapper.updateById(row) != 1) throw new IllegalStateException("商户配置退役失败，请刷新后重试");
        reloadShopChannelToCache(rowShopId, row.getChannel());
    }

    public PaymentMerchantConfigEntity restore(long id, int shopId) {
        PaymentMerchantConfigEntity row = merchantMapper.selectById(id);
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        if (row == null || row.getShop_id() == null || row.getShop_id() != sid) {
            throw new IllegalArgumentException("商户配置不存在");
        }
        row.setStatus("ACTIVE"); row.setEnabled(1);
        if (merchantMapper.updateById(row) != 1) throw new IllegalStateException("商户配置恢复失败，请刷新后重试");
        reloadShopChannelToCache(sid, row.getChannel());
        return row;
    }

    public Map<String, String> notifyUrlTemplates() {
        String base = publicBaseUrl == null ? "" : publicBaseUrl.trim();
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        Map<String, String> m = new LinkedHashMap<>();
        m.put("wechatPayNotify", base + "/order/pay/notify");
        m.put("wechatRefundNotify", base + "/order/refund/notify");
        m.put("alipayPayNotify", base + "/order/pay/alipay/notify");
        return m;
    }

    /** 统一下单默认支付回调（来自 app.public-base-url）。 */
    public String defaultWechatPayNotifyUrl() {
        return notifyUrlTemplates().getOrDefault("wechatPayNotify", "");
    }

    /**
     * 解析支付通知地址：DB 有值优先，否则用系统默认（避免微信 PARAM_ERROR 空 notify_url）。
     */
    public String resolveWechatPayNotifyUrl(String configured) {
        if (StringUtils.hasText(configured)) {
            return configured.trim();
        }
        return defaultWechatPayNotifyUrl();
    }

    public String defaultWechatRefundNotifyUrl() {
        return notifyUrlTemplates().getOrDefault("wechatRefundNotify", "");
    }

    public String resolveWechatRefundNotifyUrl(String configured) {
        if (StringUtils.hasText(configured)) {
            return configured.trim();
        }
        return defaultWechatRefundNotifyUrl();
    }

    @SuppressWarnings("unchecked")
    private void applyBody(PaymentMerchantConfigEntity row, Map<String, Object> body, boolean create) {
        if (body == null) {
            return;
        }
        normalizeBodyAliases(body);
        if (create || body.containsKey("channel")) {
            String ch = str(body.get("channel"));
            if (!StringUtils.hasText(ch)) {
                throw new IllegalArgumentException("channel 不能为空");
            }
            row.setChannel(ch.trim().toLowerCase());
        }
        if (create || body.containsKey("merchantKey")) {
            String mk = normalizeMerchantKey(str(body.get("merchantKey")));
            if (!StringUtils.hasText(mk)) {
                throw new IllegalArgumentException("merchantKey 不能为空");
            }
            row.setMerchant_key(mk);
        }
        putIfPresent(body, "appId", row::setApp_id);
        putIfPresent(body, "mchId", row::setMch_id);
        putIfPresent(body, "notifyUrl", row::setNotify_url);
        putIfPresent(body, "refundNotifyUrl", row::setRefund_notify_url);
        if (body.containsKey("enabled")) {
            row.setEnabled(boolToInt(parseBool(body.get("enabled"), isEnabled(row))));
        }
        if (body.containsKey("serialNo") || body.containsKey("serial_no")) {
            Object v = body.containsKey("serialNo") ? body.get("serialNo") : body.get("serial_no");
            row.setSerial_no(PaymentMerchantFieldValidator.normalizeSerialNo(str(v)));
        }
        if (body.containsKey("platformPubKeyId") || body.containsKey("platform_pub_key_id")) {
            Object v = body.containsKey("platformPubKeyId")
                    ? body.get("platformPubKeyId") : body.get("platform_pub_key_id");
            String s = str(v);
            if (!PaymentCredentialCipher.isMaskPlaceholder(s)) {
                row.setPlatform_pub_key_id(PaymentMerchantFieldValidator.normalizePlatformPubKeyId(s));
            }
        }
        if (body.containsKey("platformPubKeyRef") || body.containsKey("platform_pub_key_ref")) {
            Object v = body.containsKey("platformPubKeyRef")
                    ? body.get("platformPubKeyRef") : body.get("platform_pub_key_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                row.setPlatform_pub_key_ref(PaymentMerchantFieldValidator.normalizePlatformPubKeyRef(ref));
            }
        }
        if (body.containsKey("routingRuleJson")) {
            String rule = str(body.get("routingRuleJson"));
            validateRoutingRule(rule);
            row.setRouting_rule_json(StringUtils.hasText(rule) ? rule.trim() : null);
        }
        putIfPresent(body, "remark", row::setRemark);
        if (body.containsKey("sortOrder")) {
            Object so = body.get("sortOrder");
            if (so instanceof Number) {
                row.setSort_order(((Number) so).intValue());
            }
        }
        if (body.containsKey("apiV3Key")) {
            String k = str(body.get("apiV3Key"));
            if (StringUtils.hasText(k) && !PaymentCredentialCipher.isMaskPlaceholder(k)) {
                String apiV3Key = k.trim();
                if (apiV3Key.length() != 32) {
                    throw new IllegalArgumentException("apiV3Key 必须为 32 位");
                }
                row.setApi_v3_key_enc(credentialCipher.encrypt(apiV3Key));
            }
        }
        if (body.containsKey("apiV2Key")) {
            String k = str(body.get("apiV2Key"));
            if (StringUtils.hasText(k) && !PaymentCredentialCipher.isMaskPlaceholder(k)) {
                String apiV2Key = k.trim();
                if (apiV2Key.length() != 32) {
                    throw new IllegalArgumentException("apiV2Key 必须为 32 位");
                }
                row.setApi_v2_key_enc(credentialCipher.encrypt(apiV2Key));
            }
        }
        if (body.containsKey("privateKeyRef") || body.containsKey("private_key_ref")) {
            Object v = body.containsKey("privateKeyRef")
                    ? body.get("privateKeyRef") : body.get("private_key_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                row.setPrivate_key_ref(PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref));
            }
        }
        if (body.containsKey("clientCertP12Ref") || body.containsKey("client_cert_p12_ref")) {
            Object v = body.containsKey("clientCertP12Ref")
                    ? body.get("clientCertP12Ref") : body.get("client_cert_p12_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                String normalized = PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref);
                String lower = normalized.toLowerCase();
                if (lower.startsWith("classpath:")) {
                    throw new IllegalArgumentException("clientCertP12Ref 必须为服务器文件路径，不能使用 classpath");
                }
                if (!lower.endsWith(".p12") && !lower.endsWith(".pfx")) {
                    throw new IllegalArgumentException("clientCertP12Ref 必须指向 .p12 或 .pfx 文件");
                }
                row.setClient_cert_p12_ref(normalized);
            }
        }
        if (body.containsKey("alipayAppCertRef") || body.containsKey("alipay_app_cert_ref")) {
            Object v = body.containsKey("alipayAppCertRef")
                    ? body.get("alipayAppCertRef") : body.get("alipay_app_cert_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                row.setAlipay_app_cert_ref(PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref));
            }
        }
        if (body.containsKey("alipayPublicCertRef") || body.containsKey("alipay_public_cert_ref")) {
            Object v = body.containsKey("alipayPublicCertRef")
                    ? body.get("alipayPublicCertRef") : body.get("alipay_public_cert_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                row.setAlipay_public_cert_ref(PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref));
            }
        }
        if (body.containsKey("alipayRootCertRef") || body.containsKey("alipay_root_cert_ref")) {
            Object v = body.containsKey("alipayRootCertRef")
                    ? body.get("alipayRootCertRef") : body.get("alipay_root_cert_ref");
            String ref = str(v);
            if (StringUtils.hasText(ref) && !PaymentCredentialCipher.isMaskPlaceholder(ref)) {
                row.setAlipay_root_cert_ref(PaymentMerchantFieldValidator.normalizePrivateKeyRef(ref));
            }
        }
    }

    private static String normalizeMerchantKey(String merchantKey) {
        if (!StringUtils.hasText(merchantKey)) {
            return "default";
        }
        String k = merchantKey.trim();
        if ("1".equals(k)) {
            return "default";
        }
        if ("2".equals(k)) {
            return "small_amount";
        }
        if (!k.matches("[A-Za-z0-9._-]{1,64}")) {
            throw new IllegalArgumentException("merchantKey 仅允许 1-64 位字母、数字、点、下划线或横线");
        }
        return k;
    }

    private void validateRoutingRule(String raw) {
        if (!StringUtils.hasText(raw)) return;
        try {
            JsonNode rule = objectMapper.readTree(raw);
            if (!rule.isObject() || !"amount_and_dining".equals(rule.path("type").asText())) {
                throw new IllegalArgumentException("routingRuleJson.type 仅支持 amount_and_dining");
            }
            if (!StringUtils.hasText(rule.path("targetMerchantKey").asText())) {
                throw new IllegalArgumentException("routingRuleJson.targetMerchantKey 不能为空");
            }
            normalizeMerchantKey(rule.path("targetMerchantKey").asText());
            if (StringUtils.hasText(rule.path("defaultMerchantKey").asText())) {
                normalizeMerchantKey(rule.path("defaultMerchantKey").asText());
            }
            if (rule.has("minPaidYuan") && !rule.path("minPaidYuan").isNumber()) {
                throw new IllegalArgumentException("routingRuleJson.minPaidYuan 必须为数字");
            }
            if (rule.has("maxPaidYuan") && !rule.path("maxPaidYuan").isNumber()) {
                throw new IllegalArgumentException("routingRuleJson.maxPaidYuan 必须为数字");
            }
            if (rule.has("diningTypes") && !rule.path("diningTypes").isArray()) {
                throw new IllegalArgumentException("routingRuleJson.diningTypes 必须为数组");
            }
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("routingRuleJson 不是有效 JSON");
        }
    }

    private static boolean isEnabled(PaymentMerchantConfigEntity row) {
        return row != null && row.getEnabled() != null && row.getEnabled() != 0
                && !"RETIRED".equalsIgnoreCase(row.getStatus());
    }

    private static String normalizedStatus(PaymentMerchantConfigEntity row) {
        return row != null && StringUtils.hasText(row.getStatus()) ? row.getStatus().trim().toUpperCase() : "ACTIVE";
    }

    private static int currentVersion(PaymentMerchantConfigEntity row) {
        return row != null && row.getCredential_version() != null && row.getCredential_version() > 0
                ? row.getCredential_version() : 1;
    }

    private static PaymentMerchantConfigEntity copy(PaymentMerchantConfigEntity source) {
        PaymentMerchantConfigEntity target = new PaymentMerchantConfigEntity();
        org.springframework.beans.BeanUtils.copyProperties(source, target);
        return target;
    }

    private void snapshot(PaymentMerchantConfigEntity row) {
        if (row == null || row.getId() == null) return;
        PaymentMerchantConfigHistoryEntity h = new PaymentMerchantConfigHistoryEntity();
        h.setMerchant_config_id(row.getId()); h.setCredential_version(currentVersion(row));
        h.setShop_id(row.getShop_id()); h.setChannel(row.getChannel()); h.setMerchant_key(row.getMerchant_key());
        h.setApp_id(row.getApp_id()); h.setMch_id(row.getMch_id()); h.setNotify_url(row.getNotify_url());
        h.setRefund_notify_url(row.getRefund_notify_url()); h.setApi_v3_key_enc(row.getApi_v3_key_enc());
        h.setApi_v2_key_enc(row.getApi_v2_key_enc()); h.setSerial_no(row.getSerial_no());
        h.setPlatform_pub_key_id(row.getPlatform_pub_key_id()); h.setPlatform_pub_key_ref(row.getPlatform_pub_key_ref());
        h.setPrivate_key_ref(row.getPrivate_key_ref()); h.setClient_cert_p12_ref(row.getClient_cert_p12_ref());
        h.setCreated_at(new java.util.Date());
        merchantHistoryMapper.insert(h);
    }

    private List<String> getWechatRowMissingFields(PaymentMerchantConfigEntity row) {
        List<String> missing = new ArrayList<>(PaymentMerchantReadiness.missingFields(row));
        if (row == null || !StringUtils.hasText(row.getApi_v3_key_enc())) {
            return missing;
        }
        try {
            String apiV3Key = credentialCipher.decrypt(row.getApi_v3_key_enc());
            if (apiV3Key == null || apiV3Key.length() != 32) {
                addMissingField(missing, "apiV3Key");
            }
        } catch (RuntimeException e) {
            log.warn("微信支付商户 APIv3 密钥解密失败，merchantConfigId={}", row.getId());
            addMissingField(missing, "apiV3Key");
        }
        return missing;
    }

    private static void addMissingField(List<String> missing, String field) {
        if (!missing.contains(field)) {
            missing.add(field);
        }
    }

    private static String maskRef(String ref) {
        if (!StringUtils.hasText(ref)) {
            return "";
        }
        if (ref.startsWith("classpath:")) {
            return ref;
        }
        return PaymentCredentialCipher.maskSecret(ref);
    }

    /** 编辑表单：classpath 路径原样返回，服务器绝对路径仍脱敏。 */
    private static String revealRefForEdit(String ref) {
        if (!StringUtils.hasText(ref)) {
            return "";
        }
        String t = ref.trim();
        if (t.startsWith("classpath:")) {
            return t;
        }
        return PaymentCredentialCipher.maskSecret(t);
    }

    private static void normalizeBodyAliases(Map<String, Object> body) {
        copyAlias(body, "app_id", "appId");
        copyAlias(body, "mch_id", "mchId");
        copyAlias(body, "notify_url", "notifyUrl");
        copyAlias(body, "refund_notify_url", "refundNotifyUrl");
        copyAlias(body, "merchant_key", "merchantKey");
        copyAlias(body, "api_v3_key", "apiV3Key");
        copyAlias(body, "api_v2_key", "apiV2Key");
        copyAlias(body, "serial_no", "serialNo");
        copyAlias(body, "platform_pub_key_id", "platformPubKeyId");
        copyAlias(body, "platform_pub_key_ref", "platformPubKeyRef");
        copyAlias(body, "private_key_ref", "privateKeyRef");
        copyAlias(body, "client_cert_p12_ref", "clientCertP12Ref");
        copyAlias(body, "alipay_app_cert_ref", "alipayAppCertRef");
        copyAlias(body, "alipay_public_cert_ref", "alipayPublicCertRef");
        copyAlias(body, "alipay_root_cert_ref", "alipayRootCertRef");
        copyAlias(body, "routing_rule_json", "routingRuleJson");
        copyAlias(body, "sort_order", "sortOrder");
    }

    private static void copyAlias(Map<String, Object> body, String snake, String camel) {
        if (body.containsKey(snake) && !body.containsKey(camel)) {
            body.put(camel, body.get(snake));
        }
    }

    private static Object firstPresent(Map<String, Object> body, String... keys) {
        for (String k : keys) {
            if (body.containsKey(k) && body.get(k) != null) {
                return body.get(k);
            }
        }
        return null;
    }

    private static Long parseLongId(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Number) {
            return ((Number) raw).longValue();
        }
        String s = raw.toString().trim();
        if (!StringUtils.hasText(s)) {
            return null;
        }
        try {
            return Long.parseLong(s);
        } catch (NumberFormatException ex) {
            throw new IllegalArgumentException("id 格式错误：" + s);
        }
    }

    private Path resolvePrivateKeyUploadDir() throws IOException {
        String configured = StringUtils.hasText(privateKeyUploadDir) ? privateKeyUploadDir.trim()
                : "/www/wwwroot/upload/payment-keys";
        if (configured.startsWith("classpath:")) {
            throw new IllegalArgumentException("payment.private-key-upload-dir 不能使用 classpath:，上传文件必须保存到可写服务器目录");
        }
        boolean explicitAbsolute = Paths.get(configured).isAbsolute();
        Path path = Paths.get(configured);
        if (!path.isAbsolute()) {
            path = Paths.get(System.getProperty("user.dir"), configured);
        }
        path = path.normalize();
        try {
            return ensureWritableDirectory(path);
        } catch (IOException ex) {
            if (explicitAbsolute) {
                throw ex;
            }
            Path fallback = Paths.get(System.getProperty("user.dir"), "payment-keys").normalize();
            try {
                Path resolved = ensureWritableDirectory(fallback);
                log.warn("支付私钥上传目录不可写，已回退到进程工作目录。configured={}, fallback={}, reason={}",
                        path, fallback, ex.getMessage());
                return resolved;
            } catch (IOException fallbackEx) {
                throw new IOException(ex.getMessage() + "；回退目录 " + fallback + " 也不可写：" + fallbackEx.getMessage(),
                        fallbackEx);
            }
        }
    }

    private Path ensureWritableDirectory(Path path) throws IOException {
        try {
            Files.createDirectories(path);
        } catch (AccessDeniedException e) {
            throw new IOException(buildUploadDirErrorMessage(path, "无法创建目录", e), e);
        }
        if (!Files.isDirectory(path)) {
            throw new IOException("payment.private-key-upload-dir 不是目录：" + path);
        }
        Path probe = path.resolve(".write-probe-" + UUID.randomUUID());
        try {
            Files.write(probe, "ok".getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
            Files.deleteIfExists(probe);
        } catch (IOException e) {
            throw new IOException(buildUploadDirErrorMessage(path, "目录探测写入失败", e), e);
        }
        return path;
    }

    private static String buildUploadDirErrorMessage(Path path, String action, Exception cause) {
        String user = System.getProperty("user.name", "unknown");
        Path abs = path.toAbsolutePath().normalize();
        String hint = "请 SSH 执行: mkdir -p " + abs + " && chown -R www:www " + abs
                + " && chmod 750 " + abs + "（Java 运行用户见日志 user.name，宝塔多为 www）";
        String detail = cause != null && StringUtils.hasText(cause.getMessage()) ? cause.getMessage() : action;
        return action + "：" + path + "（当前 JVM 用户=" + user + "，" + detail + "）。" + hint;
    }

    private static void validatePrivateKeyPem(String pem) {
        if (!StringUtils.hasText(pem)) {
            throw new IllegalArgumentException("PEM 私钥文件为空");
        }
        boolean pkcs8 = pem.contains("-----BEGIN PRIVATE KEY-----") && pem.contains("-----END PRIVATE KEY-----");
        boolean rsa = pem.contains("-----BEGIN RSA PRIVATE KEY-----") && pem.contains("-----END RSA PRIVATE KEY-----");
        if (!pkcs8 && !rsa) {
            throw new IllegalArgumentException("文件不是有效的 PEM 私钥（需包含 BEGIN/END PRIVATE KEY）");
        }
        if (pem.contains("-----BEGIN CERTIFICATE-----") || pem.contains("-----BEGIN PUBLIC KEY-----")) {
            throw new IllegalArgumentException("请上传商户私钥 PEM，不要上传证书或公钥文件");
        }
    }

    private static String sanitizeFilePart(String raw) {
        String v = StringUtils.hasText(raw) ? raw.trim().toLowerCase() : "default";
        return v.replaceAll("[^a-z0-9._-]", "_");
    }

    private static void restrictOwnerRead(Path target) {
        try {
            java.io.File f = target.toFile();
            f.setReadable(false, false);
            f.setWritable(false, false);
            f.setReadable(true, true);
            f.setWritable(true, true);
        } catch (Exception ignore) {
            // Windows/部分文件系统不支持精细权限，忽略即可。
        }
    }

    private static String normalizePathRef(Path path) {
        return path.toAbsolutePath().normalize().toString().replace('\\', '/');
    }

    private static String str(Object o) {
        return o == null ? null : o.toString();
    }

    private static void putIfPresent(Map<String, Object> body, String key, java.util.function.Consumer<String> setter) {
        if (body.containsKey(key)) {
            Object v = body.get(key);
            setter.accept(v == null ? null : v.toString());
        }
    }

    private static boolean parseBool(Object raw, boolean def) {
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        if (raw == null) {
            return def;
        }
        String s = raw.toString().trim();
        return "1".equals(s) || "true".equalsIgnoreCase(s);
    }

    private static int boolToInt(boolean v) {
        return v ? 1 : 0;
    }
}
