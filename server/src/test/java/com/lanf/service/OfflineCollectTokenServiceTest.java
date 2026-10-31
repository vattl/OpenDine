package com.lanf.service;

import com.lanf.dto.OfflineCollectTokenPayload;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OfflineCollectTokenServiceTest {

    @Test
    void tokenKeepsMerchantRoutingForTheJumpEndpoint() {
        OfflineCollectTokenService service = new OfflineCollectTokenService();

        String token = service.newToken(7, "WECHAT", "2");

        Optional<OfflineCollectTokenPayload> resolved = service.resolve(token);
        assertTrue(resolved.isPresent());
        assertEquals(7, resolved.get().getShopId());
        assertEquals("wechat", resolved.get().getChannel());
        assertEquals("2", resolved.get().getMerchantId());
    }
}
