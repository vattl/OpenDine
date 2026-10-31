package com.lanf.payment.channel.wechat;

import com.lanf.payment.PaymentChannels;
import com.lanf.payment.config.ResolvedWechatMerchant;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.service.PaymentMerchantConfigService;
import com.lanf.payment.support.PaymentMerchantReadiness;
import com.wechat.pay.contrib.apache.httpclient.auth.PrivateKeySigner;
import com.wechat.pay.contrib.apache.httpclient.util.PemUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 微信支付商户密钥（仅从 DB {@link PaymentMerchantConfigService} 加载，无 application.yml 回退）。
 */
@Component
public class WechatMerchantKeyStore {

    private static final Logger log = LoggerFactory.getLogger(WechatMerchantKeyStore.class);

    @Autowired
    private PaymentMerchantConfigService paymentMerchantConfigService;
    @Autowired
    private WechatPlatformPublicKeyLoader platformPublicKeyLoader;

    private final ConcurrentHashMap<String, PrivateKey> privateKeyByRef = new ConcurrentHashMap<>();

    /**
     * 从 DB 解析商户配置与密钥，供 JSAPI 下单使用。
     */
    public ResolvedMerchant resolveForPay(Integer shopId, String legacyMerchantId, String merchantKey) {
        String legacy = "2".equals(legacyMerchantId) ? "2" : "1";
        String mk = normalizeMerchantKey(StringUtils.hasText(merchantKey) ? merchantKey : legacyMerchantId);
        if (StringUtils.hasText(merchantKey)) {
            if ("2".equals(merchantKey) || "small_amount".equals(merchantKey)) {
                legacy = "2";
                mk = "small_amount";
            }
        }
        PaymentMerchantConfigEntity dbRow =
                paymentMerchantConfigService.findMergedRow(shopId, PaymentChannels.WECHAT, mk);
        ResolvedWechatMerchant cfg = paymentMerchantConfigService.resolveWechat(shopId, mk);

        ResolvedMerchant r = new ResolvedMerchant();
        r.legacyMerchantId = legacy;
        r.merchantKey = mk;

        if (cfg == null) {
            r.privateKeyRefUsed = "";
            buildAudit(r, shopId, mk, legacy, dbRow, cfg, new PrivateKeyLoadResult(null, false));
            log.warn("[wx-pay] 门店未配置可用微信商户 shopId={} merchantKey={}", shopId, mk);
            return r;
        }

        r.appId = cfg.appId;
        r.mchId = cfg.mchId;
        r.notifyUrl = paymentMerchantConfigService.resolveWechatPayNotifyUrl(cfg.notifyUrl);
        r.refundNotifyUrl = paymentMerchantConfigService.resolveWechatRefundNotifyUrl(cfg.refundNotifyUrl);
        if (!StringUtils.hasText(cfg.notifyUrl) && StringUtils.hasText(r.notifyUrl)) {
            log.warn("[wx-pay] 商户 notify_url 为空，统一下单使用默认回调 shopId={} url={}", shopId, r.notifyUrl);
        }
        r.platformPubKeyId = cfg.platformPubKeyId;
        r.apiV3Key = cfg.apiV3Key;
        r.apiV2Key = cfg.apiV2Key;
        r.clientCertP12Ref = cfg.clientCertP12Ref;
        r.dbConfigId = cfg.dbConfigId;
        r.dbConfigVersion = cfg.dbCredentialVersion;
        r.dbShopId = cfg.dbShopId;
        r.privateKeyRefUsed = cfg.privateKeyRef;

        PrivateKeyLoadResult pkLoad = loadPrivateKeyWithTrace(cfg.privateKeyRef);
        r.privateKey = pkLoad.key;
        r.serialNo = cfg.serialNo;
        r.signer = r.privateKey != null ? new PrivateKeySigner(r.serialNo, r.privateKey) : null;
        r.wechatPublicKey = resolvePlatformPublicKey(cfg.platformPubKeyRef);

        buildAudit(r, shopId, mk, legacy, dbRow, cfg, pkLoad);
        log.info("[wx-pay] 商户配置解析 shopId={} {}", shopId, r.payAuthAudit.toLogLine());
        if (!r.payAuthAudit.issues.isEmpty()) {
            log.warn("[wx-pay] 商户配置潜在问题 shopId={} issues={}", shopId, r.payAuthAudit.issues);
        }
        return r;
    }

    /** 后续查单/退款按创建时固化的配置版本解析。 */
    public ResolvedMerchant resolveBound(Long configId, Integer version) {
        ResolvedWechatMerchant cfg = paymentMerchantConfigService.resolveWechatBound(configId, version);
        if (cfg == null) return null;
        ResolvedMerchant r = new ResolvedMerchant();
        r.legacyMerchantId = cfg.legacyMerchantId; r.merchantKey = cfg.merchantKey;
        r.appId = cfg.appId; r.mchId = cfg.mchId;
        r.notifyUrl = paymentMerchantConfigService.resolveWechatPayNotifyUrl(cfg.notifyUrl);
        r.refundNotifyUrl = paymentMerchantConfigService.resolveWechatRefundNotifyUrl(cfg.refundNotifyUrl);
        r.platformPubKeyId = cfg.platformPubKeyId; r.apiV3Key = cfg.apiV3Key; r.apiV2Key = cfg.apiV2Key;
        r.clientCertP12Ref = cfg.clientCertP12Ref; r.privateKeyRefUsed = cfg.privateKeyRef;
        PrivateKeyLoadResult pk = loadPrivateKeyWithTrace(cfg.privateKeyRef);
        r.privateKey = pk.key; r.serialNo = cfg.serialNo;
        r.signer = r.privateKey == null ? null : new PrivateKeySigner(r.serialNo, r.privateKey);
        r.wechatPublicKey = resolvePlatformPublicKey(cfg.platformPubKeyRef);
        r.dbConfigId = cfg.dbConfigId; r.dbConfigVersion = cfg.dbCredentialVersion; r.dbShopId = cfg.dbShopId;
        return r;
    }

    /** 按交易固化版本解析并校验门店归属；shop_id=0 仅表示交易创建时已固化的全局模板。 */
    public ResolvedMerchant resolveBound(Long configId, Integer version, Integer expectedShopId) {
        ResolvedMerchant resolved = resolveBound(configId, version);
        if (resolved == null || expectedShopId == null) return resolved;
        int boundShopId = resolved.dbShopId != null ? resolved.dbShopId : Integer.MIN_VALUE;
        if (boundShopId != 0 && boundShopId != expectedShopId) {
            log.error("[wx-pay] 固化商户跨店绑定被拒绝 configId={} version={} expectedShopId={} actualShopId={}",
                    configId, version, expectedShopId, resolved.dbShopId);
            return null;
        }
        return resolved;
    }

    private static String normalizeMerchantKey(String raw) {
        if (!StringUtils.hasText(raw) || "1".equals(raw.trim())) return "default";
        if ("2".equals(raw.trim())) return "small_amount";
        return raw.trim();
    }

    private void buildAudit(ResolvedMerchant r, Integer shopId, String mk, String legacy,
                            PaymentMerchantConfigEntity dbRow, ResolvedWechatMerchant cfg,
                            PrivateKeyLoadResult pkLoad) {
        int sidNorm = shopId != null ? shopId : 0;
        String configSource = "none";
        if (dbRow != null) {
            configSource = dbRow.getShop_id() != null && dbRow.getShop_id() > 0
                    && dbRow.getShop_id().equals(sidNorm) ? "shop_db" : "global_db";
        }
        WechatPayCredentialAudit.PayAuthAuditInput ain = new WechatPayCredentialAudit.PayAuthAuditInput();
        ain.shopId = shopId;
        ain.merchantKey = mk;
        ain.legacyMerchantId = legacy;
        ain.dbConfigId = cfg != null ? cfg.dbConfigId : (dbRow != null ? dbRow.getId() : null);
        ain.dbShopId = cfg != null ? cfg.dbShopId : (dbRow != null ? dbRow.getShop_id() : null);
        ain.configSource = configSource;
        ain.dbPrivateKeyRef = cfg != null ? cfg.privateKeyRef : null;
        ain.dbSerialNo = cfg != null ? cfg.serialNo : null;
        ain.privateKeyRefUsed = r.privateKeyRefUsed;
        ain.privateKeyLoadedFromConfiguredRef = pkLoad.loadedFromConfiguredRef;
        ain.privateKeyFallbackYml = false;
        ain.serialNoUsedInAuth = r.serialNo;
        ain.mchIdUsed = r.mchId;
        ain.appIdUsed = r.appId;
        ain.apiV3KeySource = cfg != null && StringUtils.hasText(cfg.apiV3Key) ? "db" : "none";
        ain.apiV3KeyLooksLikeMiniProgramSecret = false;
        if (cfg == null) {
            ain.issuesPreset = new ArrayList<>();
            ain.issuesPreset.add("未配置或未启用微信支付商户（" + mk + "）");
            if (dbRow != null) {
                ain.issuesPreset.addAll(PaymentMerchantReadiness.missingFields(dbRow));
            }
        }
        r.payAuthAudit = WechatPayCredentialAudit.build(ain);
    }

    /** 运营端更新商户配置后清空私钥缓存，避免同路径文件已替换仍用旧密钥。 */
    public void invalidatePrivateKeyCache() {
        privateKeyByRef.clear();
    }

    public WechatPayCredentialAudit.PayAuthAudit auditPayConfig(Integer shopId, String legacyMerchantId) {
        ResolvedMerchant m = resolveForPay(shopId, legacyMerchantId, null);
        return m != null ? m.payAuthAudit : null;
    }

    /**
     * 回调验签：按 {@code Wechatpay-Serial} 匹配 DB 中所有启用且字段完整的商户行。
     */
    public NotifyContext resolveNotifyContext(HttpServletRequest request, String body) throws Exception {
        String serial = request.getHeader("Wechatpay-Serial");
        if (!StringUtils.hasText(serial)) {
            return null;
        }
        serial = serial.trim();
        List<PaymentMerchantConfigService.NotifyCryptoMatch> matches =
                paymentMerchantConfigService.findNotifyCryptoMatches(serial);
        if (matches.isEmpty()) {
            log.error("公钥序列号无匹配 DB 配置 - 回调: {}", serial);
            return null;
        }

        PublicKey publicKey = null;
        LinkedHashSet<String> apiV3Keys = new LinkedHashSet<>();
        String legacyMerchantId = null;
        for (PaymentMerchantConfigService.NotifyCryptoMatch match : matches) {
            PublicKey pk = resolvePlatformPublicKey(match.platformPubKeyRef);
            if (pk != null && publicKey == null) {
                publicKey = pk;
            }
            if (StringUtils.hasText(match.apiV3Key)) {
                apiV3Keys.add(match.apiV3Key.trim());
            }
            if (legacyMerchantId == null && StringUtils.hasText(match.legacyMerchantId)) {
                legacyMerchantId = match.legacyMerchantId;
            }
        }
        if (publicKey == null) {
            log.error("无法加载微信平台公钥 - serial={}", serial);
            return null;
        }

        String signature = request.getHeader("Wechatpay-Signature");
        String timestamp = request.getHeader("Wechatpay-Timestamp");
        String nonce = request.getHeader("Wechatpay-Nonce");
        boolean signatureValid = WechatPayV3Crypto.verifyNotifySignature(
                body, timestamp, nonce, signature, publicKey);

        NotifyContext ctx = new NotifyContext();
        ctx.signatureValid = signatureValid;
        ctx.legacyMerchantId = legacyMerchantId != null ? legacyMerchantId : "1";
        ctx.apiV3KeyCandidates = new ArrayList<>(apiV3Keys);
        ctx.apiV3Key = ctx.apiV3KeyCandidates.isEmpty() ? null : ctx.apiV3KeyCandidates.get(0);
        if (!signatureValid) {
            log.error("微信支付回调签名验证失败 serial={}", serial);
        }
        return ctx;
    }

    private PublicKey resolvePlatformPublicKey(String ref) {
        if (!StringUtils.hasText(ref)) {
            return null;
        }
        try {
            return platformPublicKeyLoader.load(ref.trim());
        } catch (Exception e) {
            log.warn("从 DB 加载微信平台公钥失败 ref={}: {}", ref, e.getMessage());
            return null;
        }
    }

    private PrivateKeyLoadResult loadPrivateKeyWithTrace(String ref) {
        if (!StringUtils.hasText(ref)) {
            return new PrivateKeyLoadResult(null, false);
        }
        String t = ref.trim();
        try {
            PrivateKey pk = privateKeyByRef.computeIfAbsent(t, k -> {
                try {
                    return loadPrivateKey(k);
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            });
            return new PrivateKeyLoadResult(pk, true);
        } catch (Exception e) {
            log.warn("加载商户私钥失败 ref={}: {}", t, e.getMessage());
            return new PrivateKeyLoadResult(null, false);
        }
    }

    private static final class PrivateKeyLoadResult {
        final PrivateKey key;
        final boolean loadedFromConfiguredRef;

        PrivateKeyLoadResult(PrivateKey key, boolean loadedFromConfiguredRef) {
            this.key = key;
            this.loadedFromConfiguredRef = loadedFromConfiguredRef;
        }
    }

    private PrivateKey loadPrivateKey(String privateKeyPath) throws Exception {
        InputStream is;
        if (privateKeyPath.startsWith("classpath:")) {
            String path = privateKeyPath.replace("classpath:", "");
            is = getClass().getClassLoader().getResourceAsStream(path);
            if (is == null) {
                throw new FileNotFoundException("私钥文件不存在于类路径: " + path);
            }
        } else {
            File file = new File(privateKeyPath);
            if (!file.exists()) {
                throw new FileNotFoundException("私钥文件不存在: " + privateKeyPath);
            }
            is = new FileInputStream(file);
        }
        return PemUtil.loadPrivateKey(is);
    }

    public static final class ResolvedMerchant {
        public String legacyMerchantId;
        public String merchantKey;
        public String appId;
        public String mchId;
        public String notifyUrl;
        public String refundNotifyUrl;
        public String apiV3Key;
        public String apiV2Key;
        public String serialNo;
        public String platformPubKeyId;
        public String privateKeyRefUsed;
        public String clientCertP12Ref;
        public Long dbConfigId;
        public Integer dbConfigVersion;
        public Integer dbShopId;
        public WechatPayCredentialAudit.PayAuthAudit payAuthAudit;
        public PrivateKey privateKey;
        public PrivateKeySigner signer;
        public PublicKey wechatPublicKey;
    }

    public static final class NotifyContext {
        public String legacyMerchantId;
        public String apiV3Key;
        public List<String> apiV3KeyCandidates = new ArrayList<>();
        public boolean signatureValid;
    }
}
