package com.lanf.payment.channel.wechat;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 从 classpath 路径或内联 PEM 加载微信支付平台公钥（验签用）。
 */
@Component
public class WechatPlatformPublicKeyLoader {

    private static final Logger log = LoggerFactory.getLogger(WechatPlatformPublicKeyLoader.class);

    private final ConcurrentHashMap<String, PublicKey> cache = new ConcurrentHashMap<>();

    public void invalidateAll() {
        cache.clear();
    }

    public PublicKey load(String ref) throws Exception {
        if (!StringUtils.hasText(ref)) {
            return null;
        }
        String key = ref.trim();
        return cache.computeIfAbsent(key, k -> {
            try {
                return loadUncached(k);
            } catch (IllegalArgumentException e) {
                throw e;
            } catch (Exception e) {
                throw new IllegalStateException("加载微信平台公钥失败 ref=" + maskRef(k) + ": " + e.getMessage(), e);
            }
        });
    }

    private PublicKey loadUncached(String ref) throws Exception {
        if (ref.contains("BEGIN PRIVATE KEY") || ref.contains("BEGIN RSA PRIVATE KEY")) {
            throw new IllegalArgumentException("微信平台公钥文件不能包含私钥");
        }
        if (ref.contains("BEGIN PUBLIC KEY") || ref.contains("BEGIN CERTIFICATE")) {
            return parsePemPublicKey(ref);
        }
        InputStream is = openStream(ref);
        try {
            return parsePemPublicKey(readStream(is));
        } finally {
            if (is != null) {
                try {
                    is.close();
                } catch (IOException e) {
                    log.warn("关闭公钥输入流失败", e);
                }
            }
        }
    }

    private static InputStream openStream(String pubKeyPath) throws Exception {
        if (pubKeyPath.startsWith("classpath:")) {
            String path = pubKeyPath.replace("classpath:", "").trim();
            InputStream is = WechatPlatformPublicKeyLoader.class.getClassLoader().getResourceAsStream(path);
            if (is == null) {
                is = Thread.currentThread().getContextClassLoader().getResourceAsStream(path);
            }
            if (is == null) {
                throw new FileNotFoundException("公钥文件不存在于类路径: " + path);
            }
            return is;
        }
        File pubFile = new File(pubKeyPath);
        if (!pubFile.exists()) {
            throw new FileNotFoundException("公钥文件不存在: " + pubFile);
        }
        return new FileInputStream(pubFile);
    }

    private static String readStream(InputStream is) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            sb.append(line).append('\n');
        }
        return sb.toString();
    }

    public static PublicKey parsePemPublicKey(String pemText) throws Exception {
        if (pemText.contains("-----BEGIN PRIVATE KEY-----")
                || pemText.contains("-----BEGIN RSA PRIVATE KEY-----")) {
            throw new IllegalArgumentException("微信平台公钥文件不能包含私钥");
        }
        if (pemText.contains("-----BEGIN CERTIFICATE-----")) {
            CertificateFactory factory = CertificateFactory.getInstance("X.509");
            X509Certificate certificate = (X509Certificate) factory.generateCertificate(
                    new ByteArrayInputStream(pemText.getBytes(StandardCharsets.UTF_8)));
            PublicKey publicKey = certificate.getPublicKey();
            if (!"RSA".equalsIgnoreCase(publicKey.getAlgorithm())) {
                throw new IllegalArgumentException("微信平台证书必须包含 RSA 公钥");
            }
            return publicKey;
        }
        BufferedReader reader = new BufferedReader(new StringReader(pemText));
        StringBuilder publicKeyPem = new StringBuilder();
        String line;
        boolean inPublicKeyBlock = false;
        while ((line = reader.readLine()) != null) {
            if (line.contains("-----BEGIN PUBLIC KEY-----")) {
                inPublicKeyBlock = true;
                publicKeyPem.append(line);
            } else if (line.contains("-----END PUBLIC KEY-----")) {
                inPublicKeyBlock = false;
                publicKeyPem.append(line);
            } else if (inPublicKeyBlock) {
                publicKeyPem.append(line);
            }
        }
        if (publicKeyPem.length() == 0) {
            throw new IllegalArgumentException("文件不是有效的微信平台公钥或 X.509 证书");
        }
        byte[] publicKeyBytes = Base64.getDecoder().decode(
                publicKeyPem.toString()
                        .replace("-----BEGIN PUBLIC KEY-----", "")
                        .replace("-----END PUBLIC KEY-----", "")
                        .replaceAll("\\s+", ""));
        X509EncodedKeySpec keySpec = new X509EncodedKeySpec(publicKeyBytes);
        return KeyFactory.getInstance("RSA").generatePublic(keySpec);
    }

    private static String maskRef(String ref) {
        if (ref == null) {
            return "";
        }
        if (ref.startsWith("classpath:") || ref.length() <= 24) {
            return ref;
        }
        return ref.substring(0, 12) + "...(len=" + ref.length() + ")";
    }
}
