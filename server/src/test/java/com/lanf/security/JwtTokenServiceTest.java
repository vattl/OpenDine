package com.lanf.security;

import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class JwtTokenServiceTest {

    private static final String CURRENT = "current-secret-must-have-at-least-32-bytes";
    private static final String PREVIOUS = "previous-secret-must-have-at-least-32-bytes";

    @Test
    void validatesTokensSignedWithCurrentSecret() {
        JwtTokenService service = new JwtTokenService(CURRENT, PREVIOUS);

        String token = service.createToken("7", "admin", 60_000,
                Collections.singletonMap("tokenVersion", 3));
        Claims claims = service.parseToken(token);

        assertEquals("7", claims.getId());
        assertEquals("admin", claims.getSubject());
        assertEquals(3, ((Number) claims.get("tokenVersion")).intValue());
    }

    @Test
    void acceptsPreviousSecretDuringRotationWindow() {
        JwtTokenService oldService = new JwtTokenService(PREVIOUS, "");
        String oldToken = oldService.createToken("7", "admin", 60_000, Collections.emptyMap());

        JwtTokenService rotatedService = new JwtTokenService(CURRENT, PREVIOUS);

        assertEquals("7", rotatedService.parseToken(oldToken).getId());
    }

    @Test
    void rejectsUnknownSigningSecret() {
        JwtTokenService foreignService = new JwtTokenService(
                "foreign-secret-must-have-at-least-32-bytes", "");
        String token = foreignService.createToken("7", "admin", 60_000, Collections.emptyMap());

        JwtTokenService service = new JwtTokenService(CURRENT, PREVIOUS);

        assertThrows(RuntimeException.class, () -> service.parseToken(token));
    }

    @Test
    void refusesMissingOrWeakCurrentSecret() {
        assertThrows(IllegalStateException.class, () -> new JwtTokenService("", ""));
        assertThrows(IllegalStateException.class, () -> new JwtTokenService("short", ""));
    }
}
