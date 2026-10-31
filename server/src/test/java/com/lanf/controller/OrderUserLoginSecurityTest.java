package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.security.JwtTokenService;
import com.lanf.service.WechatMiniProgramAuthService;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderUserLoginSecurityTest {

    @Test
    @SuppressWarnings("unchecked")
    void authenticatedIdentityOverridesClientOpenidAndRemovesWechatCode() {
        OrderController controller = new OrderController();
        Map<String, String> clientParams = new HashMap<>();
        clientParams.put("openid", "attacker-openid");
        clientParams.put("wxCode", "code-for-another-user");

        Map<String, String> bound = ReflectionTestUtils.invokeMethod(
                controller, "bindAuthenticatedOpenid", clientParams, "owner-openid");

        assertEquals("owner-openid", bound.get("openid"));
        assertEquals(false, bound.containsKey("wxCode"));
        assertEquals("attacker-openid", clientParams.get("openid"));
    }

    @Test
    void codeExchangeIssuesServerSignedUserToken() {
        JwtTokenService tokens = new JwtTokenService(
                "test-login-secret-must-have-at-least-32-bytes", "");
        WechatMiniProgramAuthService auth = mock(WechatMiniProgramAuthService.class);
        when(auth.exchangeCodeForOpenid("wx-code")).thenReturn("openid-owner");
        OrderController controller = new OrderController();
        ReflectionTestUtils.setField(controller, "wechatMiniProgramAuthService", auth);
        ReflectionTestUtils.setField(controller, "jwtTokenService", tokens);
        ReflectionTestUtils.setField(controller, "userTokenTtlMillis", 60_000L);

        R result = controller.getOpenid(Collections.singletonMap("code", "wx-code"));
        Claims claims = tokens.parseToken(String.valueOf(result.get("user_token")));

        assertEquals(0, result.get("code"));
        assertEquals("openid-owner", claims.getId());
        assertEquals("user", claims.getSubject());
        assertEquals(60L, result.get("expires_in"));
    }
}
