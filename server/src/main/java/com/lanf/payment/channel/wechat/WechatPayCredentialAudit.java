package com.lanf.payment.channel.wechat;

import org.springframework.util.StringUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 微信支付 APIv3 商户证书/私钥一致性诊断（仅用于日志，不含密钥内容）。
 */
public final class WechatPayCredentialAudit {

    private WechatPayCredentialAudit() {
    }

    public static final class PayAuthAudit {
        public Integer shopId;
        public String merchantKey;
        public String legacyMerchantId;
        public String orderNo;
        public Long dbConfigId;
        public Integer dbShopId;
        /** shop_db / global_db / none */
        public String configSource;
        public String dbPrivateKeyRef;
        public String dbSerialNo;
        public String ymlPrivateKeyPath;
        public String ymlSerialNo;
        public String privateKeyRefUsed;
        public boolean privateKeyLoadedFromConfiguredRef;
        public boolean privateKeyFallbackYml;
        public Boolean privateKeyFileExists;
        public Boolean privateKeyFileReadable;
        public String certPathTried;
        public String certSerialFromPem;
        public String certNotAfter;
        public Boolean certExpired;
        public String serialNoUsedInAuth;
        public Boolean serialMatchesCert;
        public String mchIdUsed;
        public String appIdUsed;
        /** db / yml / none */
        public String apiV3KeySource;
        public boolean apiV3KeyLooksLikeMiniProgramSecret;
        public final List<String> issues = new ArrayList<>();

        public void addIssue(String issue) {
            if (issue != null && !issue.isEmpty()) {
                issues.add(issue);
            }
        }

        public String toLogLine() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("orderNo", orderNo);
            m.put("shopId", shopId);
            m.put("merchantKey", merchantKey);
            m.put("legacy", legacyMerchantId);
            m.put("configSource", configSource);
            m.put("dbConfigId", dbConfigId);
            m.put("dbShopId", dbShopId);
            m.put("mchId", mchIdUsed);
            m.put("appId", maskTail(appIdUsed, 6));
            m.put("serialUsed", serialNoUsedInAuth);
            m.put("serialDb", dbSerialNo);
            m.put("serialYml", ymlSerialNo);
            m.put("certSerial", certSerialFromPem);
            m.put("certNotAfter", certNotAfter);
            m.put("certExpired", certExpired);
            m.put("serialMatchCert", serialMatchesCert);
            m.put("privateKeyRefDb", dbPrivateKeyRef);
            m.put("privateKeyRefUsed", privateKeyRefUsed);
            m.put("pkFromDbRef", privateKeyLoadedFromConfiguredRef);
            m.put("pkFallbackYml", privateKeyFallbackYml);
            m.put("pkFileExists", privateKeyFileExists);
            m.put("pkFileReadable", privateKeyFileReadable);
            m.put("certPath", certPathTried);
            m.put("apiV3KeySource", apiV3KeySource);
            m.put("apiV3LooksLikeAppSecret", apiV3KeyLooksLikeMiniProgramSecret);
            m.put("issues", issues.isEmpty() ? null : issues);
            return m.toString();
        }
    }

    public static PayAuthAudit build(PayAuthAuditInput in) {
        PayAuthAudit a = new PayAuthAudit();
        if (in.issuesPreset != null) {
            for (String issue : in.issuesPreset) {
                a.addIssue(issue);
            }
        }
        a.shopId = in.shopId;
        a.merchantKey = in.merchantKey;
        a.legacyMerchantId = in.legacyMerchantId;
        a.orderNo = in.orderNo;
        a.dbConfigId = in.dbConfigId;
        a.dbShopId = in.dbShopId;
        a.configSource = in.configSource;
        a.dbPrivateKeyRef = in.dbPrivateKeyRef;
        a.dbSerialNo = norm(in.dbSerialNo);
        a.ymlPrivateKeyPath = in.ymlPrivateKeyPath;
        a.ymlSerialNo = norm(in.ymlSerialNo);
        a.privateKeyRefUsed = in.privateKeyRefUsed;
        a.privateKeyLoadedFromConfiguredRef = in.privateKeyLoadedFromConfiguredRef;
        a.privateKeyFallbackYml = in.privateKeyFallbackYml;
        a.serialNoUsedInAuth = norm(in.serialNoUsedInAuth);
        a.mchIdUsed = in.mchIdUsed;
        a.appIdUsed = in.appIdUsed;
        a.apiV3KeySource = in.apiV3KeySource;
        a.apiV3KeyLooksLikeMiniProgramSecret = in.apiV3KeyLooksLikeMiniProgramSecret;

        probePrivateKeyFile(in.dbPrivateKeyRef, a);
        if (StringUtils.hasText(a.privateKeyRefUsed)) {
            probePrivateKeyFile(a.privateKeyRefUsed, a);
        }

        String certRef = resolveCertRefFromPrivateKeyRef(in.dbPrivateKeyRef);
        a.certPathTried = certRef;
        CertMeta certMeta = readCertMeta(certRef);
        if (certMeta != null) {
            a.certSerialFromPem = certMeta.serialHex;
            a.certNotAfter = certMeta.notAfter;
            a.certExpired = certMeta.expired;
            if (certMeta.expired != null && certMeta.expired) {
                a.addIssue("商户 API 证书已过期（notAfter=" + certMeta.notAfter + "），请在微信商户平台重新申请并更新 PEM/serial_no");
            }
        }
        if (StringUtils.hasText(a.certSerialFromPem) && StringUtils.hasText(a.serialNoUsedInAuth)) {
            a.serialMatchesCert = a.certSerialFromPem.equalsIgnoreCase(a.serialNoUsedInAuth);
            if (!a.serialMatchesCert) {
                a.addIssue("Authorization serial_no 与私钥同目录证书序列号不一致（401 常见原因）");
            }
        } else if (StringUtils.hasText(in.dbPrivateKeyRef) && !in.privateKeyLoadedFromConfiguredRef) {
            a.addIssue("DB 配置了 private_key_ref 但私钥文件未加载成功");
        }

        if (a.apiV3KeyLooksLikeMiniProgramSecret) {
            a.addIssue("api_v3_key 疑似误填小程序 secret（应为 32 位 APIv3 密钥，影响回调解密）");
        }

        if (!StringUtils.hasText(a.serialNoUsedInAuth)) {
            a.addIssue("serial_no 为空");
        }
        if (!StringUtils.hasText(a.mchIdUsed)) {
            a.addIssue("mch_id 为空");
        }
        if (!StringUtils.hasText(a.appIdUsed)) {
            a.addIssue("app_id 为空");
        }

        return a;
    }

    private static void probePrivateKeyFile(String ref, PayAuthAudit a) {
        if (!StringUtils.hasText(ref) || ref.startsWith("classpath:")) {
            return;
        }
        File f = new File(ref.trim());
        a.privateKeyFileExists = f.exists();
        a.privateKeyFileReadable = f.exists() && f.isFile() && f.canRead();
        if (!f.exists()) {
            a.addIssue("私钥文件不存在: " + ref);
        } else if (!f.canRead()) {
            a.addIssue("私钥文件无读权限: " + ref);
        }
    }

    /** 由 apiclient_key.pem 推导 apiclient_cert.pem 路径 */
    public static String resolveCertRefFromPrivateKeyRef(String privateKeyRef) {
        if (!StringUtils.hasText(privateKeyRef)) {
            return null;
        }
        String ref = privateKeyRef.trim();
        if (ref.contains("apiclient_key")) {
            return ref.replace("apiclient_key", "apiclient_cert");
        }
        if (ref.endsWith("_key.pem")) {
            return ref.substring(0, ref.length() - "_key.pem".length()) + "_cert.pem";
        }
        if (ref.endsWith("key.pem")) {
            return ref.replace("key.pem", "cert.pem");
        }
        int slash = Math.max(ref.lastIndexOf('/'), ref.lastIndexOf('\\'));
        if (slash >= 0) {
            return ref.substring(0, slash + 1) + "apiclient_cert.pem";
        }
        return "classpath:apiclient_cert.pem";
    }

    public static String readCertSerialHex(String certRef) {
        CertMeta meta = readCertMeta(certRef);
        return meta != null ? meta.serialHex : null;
    }

    private static CertMeta readCertMeta(String certRef) {
        if (!StringUtils.hasText(certRef)) {
            return null;
        }
        try (InputStream is = openStream(certRef.trim())) {
            if (is == null) {
                return null;
            }
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            X509Certificate cert = (X509Certificate) cf.generateCertificate(is);
            CertMeta meta = new CertMeta();
            meta.serialHex = cert.getSerialNumber().toString(16).toUpperCase();
            java.util.Date notAfter = cert.getNotAfter();
            if (notAfter != null) {
                meta.notAfter = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(notAfter);
                meta.expired = notAfter.before(new java.util.Date());
            }
            return meta;
        } catch (Exception e) {
            return null;
        }
    }

    private static final class CertMeta {
        String serialHex;
        String notAfter;
        Boolean expired;
    }

    public static boolean looksLikeMiniProgramSecret(String apiV3Key, String appIdSecret) {
        if (!StringUtils.hasText(apiV3Key)) {
            return false;
        }
        String k = apiV3Key.trim();
        if (StringUtils.hasText(appIdSecret) && appIdSecret.trim().equals(k)) {
            return true;
        }
        return k.length() == 32 && k.matches("[0-9a-fA-F]{32}");
    }

    private static InputStream openStream(String ref) throws Exception {
        if (ref.startsWith("classpath:")) {
            String path = ref.substring("classpath:".length());
            InputStream is = WechatPayCredentialAudit.class.getClassLoader().getResourceAsStream(path);
            if (is == null) {
                throw new java.io.FileNotFoundException("classpath:" + path);
            }
            return is;
        }
        File file = new File(ref);
        if (!file.exists()) {
            return null;
        }
        return new FileInputStream(file);
    }

    private static String norm(String s) {
        return s == null ? null : s.trim().toUpperCase();
    }

    private static String maskTail(String s, int tailLen) {
        if (!StringUtils.hasText(s) || s.length() <= tailLen) {
            return s;
        }
        return "..." + s.substring(s.length() - tailLen);
    }

    public static final class PayAuthAuditInput {
        public Integer shopId;
        public String merchantKey;
        public String legacyMerchantId;
        public String orderNo;
        public Long dbConfigId;
        public Integer dbShopId;
        public String configSource;
        public String dbPrivateKeyRef;
        public String dbSerialNo;
        public String ymlPrivateKeyPath;
        public String ymlSerialNo;
        public String privateKeyRefUsed;
        public boolean privateKeyLoadedFromConfiguredRef;
        public boolean privateKeyFallbackYml;
        public String serialNoUsedInAuth;
        public String mchIdUsed;
        public String appIdUsed;
        public String apiV3KeySource;
        public boolean apiV3KeyLooksLikeMiniProgramSecret;
        public List<String> issuesPreset;
    }
}
