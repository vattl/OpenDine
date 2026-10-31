package com.lanf.integration.service;

import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.ZsqCancelResult;
import org.junit.jupiter.api.Test;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ZsqDeliveryCancellationTest {

    @Test
    void dispatchedOrderMustUseConfirmedOpenOrderCancelEndpoint() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        when(remoteClient.cancelDeliveryOrderV2(eq("token"), any()))
                .thenReturn(Collections.singletonMap("accepted", true));
        when(remoteClient.cancelOpenOrder("token", 54237416L)).thenReturn(null);
        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, mock(ZsqOrderService.class), mock(ZsqAuthService.class), new ZsqProperties());

        ZsqCancelResult result = service.cancelTakeawayOrder(
                "token", 54237416L, "JH841794071708037", true);

        assertTrue(result.isSuccess());
        verify(remoteClient).cancelOpenOrder("token", 54237416L);
        verify(remoteClient, never()).cancelDeliveryOrderV2(eq("token"), any());
        verify(remoteClient, never()).cancelDeliveryOrder(eq("token"), any());
    }
}
