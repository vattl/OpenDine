package com.lanf.integration.service;

import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.ZsqCreateOrderPayload;
import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.remote.dto.ZsqShopAddress;
import com.lanf.integration.web.dto.CreateTakeawayOrderRequest;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ZsqOrderCoordinateBoundaryTest {

    @Test
    void convertsCanonicalGcj02ReceiverPointToZsqBd09Payload() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        ZsqOrderService service = new ZsqOrderService(remoteClient, mock(ZsqAuthService.class));
        ZsqShopAddress shop = new ZsqShopAddress();
        shop.setId(1842397L);
        shop.setIsDefault(1);
        shop.setIndustryType(1);
        when(remoteClient.listShopAddresses("auth")).thenReturn(Collections.singletonList(shop));
        when(remoteClient.createTakeawayOrder(eq("auth"), any(ZsqCreateOrderPayload.class)))
                .thenReturn(new ZsqCreateOrderResult());

        CreateTakeawayOrderRequest request = new CreateTakeawayOrderRequest();
        request.setReceiverName("测试用户");
        request.setReceiverPhone("13800138000");
        request.setReceiverAddress("鹤山市沙坪街道前进路18号");
        request.setReceiverDetail("3栋1001；配送说明：2号门进");
        request.setReceiverLatitude(22.765966);
        request.setReceiverLongitude(112.964222);
        request.setReceiverCoordinateType("gcj02");

        service.createTakeawayOrder("auth", request);

        ArgumentCaptor<ZsqCreateOrderPayload> payloadCaptor =
                ArgumentCaptor.forClass(ZsqCreateOrderPayload.class);
        verify(remoteClient).createTakeawayOrder(eq("auth"), payloadCaptor.capture());
        ZsqCreateOrderPayload payload = payloadCaptor.getValue();
        assertNotEquals("22.765966", payload.getToLatitude());
        assertNotEquals("112.964222", payload.getToLongitude());
        assertEquals(22.771679, Double.parseDouble(payload.getToLatitude()), 0.0005);
        assertEquals(112.970730, Double.parseDouble(payload.getToLongitude()), 0.0005);
        assertEquals("鹤山市沙坪街道前进路18号", payload.getToAddress());
        assertEquals("3栋1001；配送说明：2号门进", payload.getToAddressDetail());
    }
}
