package com.lanf.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtBuilder;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

/**
 * Application JWT signer/verifier with explicit current/previous key rotation.
 * Secrets must be injected at runtime and are never logged.
 */
@Component
public class JwtTokenService {

    private static final int MIN_SECRET_BYTES = 32;
    private static final String ISSUER = "diancan-server";

    private final SecretKey currentKey;
    private final SecretKey previousKey;

    public JwtTokenService(
            @Value("${auth.jwt.current-secret:}") String currentSecret,
            @Value("${auth.jwt.previous-secret:}") String previousSecret) {
        this.currentKey = toRequiredKey(currentSecret, "AUTH_JWT_CURRENT_SECRET");
        this.previousKey = toOptionalKey(previousSecret, "AUTH_JWT_PREVIOUS_SECRET");
    }

    public String createToken(String id, String subject, long ttlMillis, Map<String, Object> claims) {
        long nowMillis = System.currentTimeMillis();
        JwtBuilder builder = Jwts.builder()
                .setClaims(claims == null ? new HashMap<>() : new HashMap<>(claims))
                .setId(id)
                .setSubject(subject)
                .setIssuer(ISSUER)
                .setIssuedAt(new Date(nowMillis))
                .signWith(SignatureAlgorithm.HS256, currentKey);
        if (ttlMillis >= 0) {
            builder.setExpiration(new Date(nowMillis + ttlMillis));
        }
        return builder.compact();
    }

    public Claims parseToken(String token) {
        try {
            return parseWithKey(token, currentKey);
        } catch (RuntimeException currentFailure) {
            if (previousKey == null) {
                throw currentFailure;
            }
            return parseWithKey(token, previousKey);
        }
    }

    private Claims parseWithKey(String token, SecretKey key) {
        return Jwts.parser()
                .requireIssuer(ISSUER)
                .setSigningKey(key)
                .parseClaimsJws(token)
                .getBody();
    }

    private static SecretKey toRequiredKey(String secret, String settingName) {
        SecretKey key = toOptionalKey(secret, settingName);
        if (key == null) {
            throw new IllegalStateException(settingName + " 未配置，服务拒绝启动");
        }
        return key;
    }

    private static SecretKey toOptionalKey(String secret, String settingName) {
        if (secret == null || secret.trim().isEmpty()) {
            return null;
        }
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < MIN_SECRET_BYTES) {
            throw new IllegalStateException(settingName + " 长度必须至少为 32 字节");
        }
        return new SecretKeySpec(bytes, "HmacSHA256");
    }
}
