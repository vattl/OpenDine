package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.OrderClientRequest;
import com.lanf.entity.R;
import com.lanf.mapper.OrderClientRequestMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CashierClientRequestServiceTest {

    private CashierClientRequestService service;
    private OrderClientRequestMapper mapper;

    @BeforeEach
    void setUp() {
        service = new CashierClientRequestService();
        mapper = mock(OrderClientRequestMapper.class);
        ReflectionTestUtils.setField(service, "requestMapper", mapper);
        ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
    }

    @Test
    void missingKeyKeepsLegacyBehaviorWithoutTouchingLedger() {
        R response = service.execute(7, 9, null, "/cashier/order/quickOrder",
                () -> R.ok().put("order_no", "ORD-1"));

        assertEquals("ORD-1", response.get("order_no"));
        verify(mapper, never()).insertProcessing(any(), any(), any(), any(), any(), any());
    }

    @Test
    void firstRequestExecutesOnceAndStoresExactResponse() {
        OrderClientRequest record = record("app-1", "/cashier/order/quickOrder", "PROCESSING", null);
        when(mapper.insertProcessing(eq(7), eq(9), eq("app-1"),
                eq("/cashier/order/quickOrder"), any(), any())).thenReturn(1);
        when(mapper.lockByKey(7, "app-1")).thenReturn(record);
        when(mapper.complete(eq(10L), any())).thenReturn(1);
        AtomicInteger calls = new AtomicInteger();

        R response = service.execute(7, 9, "app-1", "/cashier/order/quickOrder", () -> {
            calls.incrementAndGet();
            return R.ok().put("order_no", "ORD-1");
        });

        assertEquals(1, calls.get());
        assertEquals("ORD-1", response.get("order_no"));
        verify(mapper).complete(eq(10L), argThat(snapshot ->
                snapshot.contains("\"code\":0") && snapshot.contains("\"order_no\":\"ORD-1\"")));
    }

    @Test
    void duplicateRequestReplaysStoredResponseWithoutExecutingBusinessLogic() {
        OrderClientRequest record = record("app-1", "/cashier/order/checkout", "COMPLETED",
                "{\"code\":0,\"order_no\":\"ORD-1\",\"idempotent\":false}");
        when(mapper.insertProcessing(eq(7), eq(9), eq("app-1"),
                eq("/cashier/order/checkout"), any(), any())).thenReturn(0);
        when(mapper.lockByKey(7, "app-1")).thenReturn(record);
        AtomicInteger calls = new AtomicInteger();

        R response = service.execute(7, 9, "app-1", "/cashier/order/checkout", () -> {
            calls.incrementAndGet();
            return R.error("不应执行");
        });

        assertEquals(0, calls.get());
        assertEquals("ORD-1", response.get("order_no"));
        assertEquals(false, response.get("idempotent"));
    }

    @Test
    void duplicateKeyUsedByAnotherEndpointIsRejected() {
        OrderClientRequest record = record("app-1", "/cashier/order/quickOrder", "COMPLETED",
                "{\"code\":0}");
        when(mapper.insertProcessing(eq(7), eq(9), eq("app-1"),
                eq("/cashier/order/checkout"), any(), any())).thenReturn(0);
        when(mapper.lockByKey(7, "app-1")).thenReturn(record);

        R response = service.execute(7, 9, "app-1", "/cashier/order/checkout", R::ok);

        assertEquals(409, response.get("code"));
    }

    @Test
    void duplicateKeyWithDifferentRequestBodyIsRejected() {
        OrderClientRequest record = record("app-1", "/cashier/order/quickOrder", "COMPLETED",
                "{\"code\":0,\"order_no\":\"ORD-1\"}");
        record.setRequest_fingerprint(service.fingerprint(
                Collections.<String, Object>singletonMap("tableNumber", "A01")));
        when(mapper.insertProcessing(eq(7), eq(9), eq("app-1"),
                eq("/cashier/order/quickOrder"), any(), any())).thenReturn(0);
        when(mapper.lockByKey(7, "app-1")).thenReturn(record);

        R response = service.execute(7, 9, "app-1", "/cashier/order/quickOrder",
                Collections.<String, Object>singletonMap("tableNumber", "A02"), R::ok);

        assertEquals(409, response.get("code"));
    }

    @Test
    void failedBusinessResponseReleasesKeyForRetry() {
        OrderClientRequest record = record("app-fail", "/cashier/order/quickOrder", "PROCESSING", null);
        when(mapper.insertProcessing(eq(7), eq(9), eq("app-fail"),
                eq("/cashier/order/quickOrder"), any(), any())).thenReturn(1);
        when(mapper.lockByKey(7, "app-fail")).thenReturn(record);

        R response = service.execute(7, 9, "app-fail", "/cashier/order/quickOrder",
                () -> R.error("打印机暂不可用"));

        assertEquals(500, response.get("code"));
        verify(mapper).deleteById(10L);
        verify(mapper, never()).complete(any(), any());
    }

    private static OrderClientRequest record(
            String key, String path, String status, String snapshot) {
        OrderClientRequest record = new OrderClientRequest();
        record.setId(10L);
        record.setShop_id(7);
        record.setClient_request_id(key);
        record.setRequest_path(path);
        record.setStatus(status);
        record.setResponse_snapshot(snapshot);
        return record;
    }
}
