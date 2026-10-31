package com.lanf.payment.channel.wechat;

import com.wechat.pay.contrib.apache.httpclient.auth.PrivateKeySigner;
import com.wechat.pay.contrib.apache.httpclient.auth.Signer;

import java.nio.charset.StandardCharsets;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 微信支付 APIv3 签名与小程序调起参数。
 */
public final class WechatPayV3Crypto {

    private WechatPayV3Crypto() {
    }

    public static String generateNonceStr() {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        StringBuilder sb = new StringBuilder();
        ThreadLocalRandom r = ThreadLocalRandom.current();
        for (int i = 0; i < 32; i++) {
            sb.append(chars.charAt(r.nextInt(chars.length())));
        }
        return sb.toString();
    }

    public static String signApiRequest(String method, String urlPath, String timestamp,
                                        String nonceStr, String body, PrivateKey privateKey) throws Exception {
        // 与微信官方「5 行、每行以 \n 结尾」一致；须与 OrderController.generatePaymentSignature 相同
        String signatureStr = String.format("%s\n%s\n%s\n%s\n%s\n", method, urlPath, timestamp, nonceStr, body);
        Signature sign = Signature.getInstance("SHA256withRSA");
        sign.initSign(privateKey);
        sign.update(signatureStr.getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(sign.sign());
    }

    public static boolean verifyNotifySignature(String body, String timestamp, String nonce,
                                                String signatureHeader, PublicKey publicKey) throws Exception {
        if (signatureHeader == null || timestamp == null || nonce == null || publicKey == null) {
            return false;
        }
        String signatureStr = String.format("%s\n%s\n%s\n", timestamp, nonce, body);
        Signature sig = Signature.getInstance("SHA256withRSA");
        sig.initVerify(publicKey);
        sig.update(signatureStr.getBytes(StandardCharsets.UTF_8));
        return sig.verify(Base64.getDecoder().decode(signatureHeader));
    }

    public static String decryptAesGcm(String ciphertext, String associatedData, String nonce,
                                       String apiV3Key) throws Exception {
        if (ciphertext == null || ciphertext.isEmpty()) {
            throw new IllegalArgumentException("加密数据不能为空");
        }
        if (apiV3Key == null || apiV3Key.length() != 32) {
            throw new IllegalArgumentException("APIv3密钥不正确（必须是32位字符串）");
        }
        byte[] ciphertextBytes = Base64.getDecoder().decode(ciphertext);
        byte[] associatedDataBytes = associatedData != null ? associatedData.getBytes(StandardCharsets.UTF_8) : new byte[0];
        byte[] nonceBytes = nonce.getBytes(StandardCharsets.UTF_8);
        javax.crypto.spec.SecretKeySpec key = new javax.crypto.spec.SecretKeySpec(
                apiV3Key.getBytes(StandardCharsets.UTF_8), "AES");
        javax.crypto.Cipher cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(javax.crypto.Cipher.DECRYPT_MODE, key, new javax.crypto.spec.GCMParameterSpec(128, nonceBytes));
        if (associatedDataBytes.length > 0) {
            cipher.updateAAD(associatedDataBytes);
        }
        byte[] decryptedData = cipher.doFinal(ciphertextBytes);
        return new String(decryptedData, StandardCharsets.UTF_8);
    }

    public static Map<String, String> buildMiniProgramPayParams(String prepayId, String appId,
                                                               PrivateKeySigner signer, PrivateKey privateKey)
            throws Exception {
        String nonceStr = generateNonceStr();
        String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
        StringBuilder signatureStr = new StringBuilder();
        signatureStr.append(appId).append("\n")
                .append(timestamp).append("\n")
                .append(nonceStr).append("\n")
                .append("prepay_id=").append(prepayId).append("\n");
        String paySign;
        if (signer != null) {
            Signer.SignatureResult signatureResult = signer.sign(signatureStr.toString().getBytes(StandardCharsets.UTF_8));
            paySign = signatureResult.getSign();
        } else {
            Signature signature = Signature.getInstance("SHA256withRSA");
            signature.initSign(privateKey);
            signature.update(signatureStr.toString().getBytes(StandardCharsets.UTF_8));
            paySign = Base64.getEncoder().encodeToString(signature.sign());
        }
        Map<String, String> params = new HashMap<>();
        params.put("timeStamp", timestamp);
        params.put("nonceStr", nonceStr);
        params.put("package", "prepay_id=" + prepayId);
        params.put("signType", "RSA");
        params.put("paySign", paySign);
        return params;
    }
}
