package com.lanf.order;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderRevisionServiceTest {

    private OrderRevisionService service;
    private IOrderService orderService;

    @BeforeEach
    void setUp() {
        service = new OrderRevisionService();
        orderService = mock(IOrderService.class);
        ReflectionTestUtils.setField(service, "orderService", orderService);
    }

    @Test
    void readExpectedVersionSupportsBothNamesAndCompatibilityOmission() {
        assertNull(service.readExpectedVersion(new HashMap<>()));

        Map<String, Object> camel = new HashMap<>();
        camel.put("expectedVersion", 12);
        assertEquals(12, service.readExpectedVersion(camel));

        Map<String, Object> snake = new HashMap<>();
        snake.put("expected_version", "13");
        assertEquals(13, service.readExpectedVersion(snake));
    }

    @Test
    void readExpectedVersionRejectsNegativeFractionalAndMalformedValues() {
        for (Object value : new Object[]{-1, 1.5d, "1.5", "abc", Long.MAX_VALUE}) {
            Map<String, Object> body = new HashMap<>();
            body.put("expectedVersion", value);
            ApiException ex = assertThrows(ApiException.class,
                    () -> service.readExpectedVersion(body));
            assertEquals(400, ex.getHttpStatus());
            assertEquals("ORDER_VERSION_INVALID", ex.getErrorCode());
        }
    }

    @Test
    void assertExpectedRejectsStaleVersionWithLatestOrderSummary() {
        Order order = order(7);

        ApiException ex = assertThrows(ApiException.class,
                () -> service.assertExpected(order, 6));

        assertEquals(409, ex.getHttpStatus());
        assertEquals("ORDER_VERSION_CONFLICT", ex.getErrorCode());
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals("ORD-REV-1", data.get("orderNo"));
        assertEquals(7, data.get("revision"));
        assertEquals("unsettled", data.get("transacStatus"));
    }

    @Test
    void assertExpectedRejectsNegativeDtoVersionAsInvalid() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.assertExpected(order(7), -1));

        assertEquals(400, ex.getHttpStatus());
        assertEquals("ORDER_VERSION_INVALID", ex.getErrorCode());
    }

    @Test
    void incrementUsesCompareAndSetAndUpdatesInMemoryRevision() {
        Order order = order(7);
        when(orderService.update(isNull(), any(Wrapper.class))).thenReturn(true);

        int next = service.increment(order, 7);

        assertEquals(8, next);
        assertEquals(8, order.getRevision());
        ArgumentCaptor<Wrapper> wrapper = ArgumentCaptor.forClass(Wrapper.class);
        verify(orderService).update(isNull(), wrapper.capture());
        String sql = wrapper.getValue().getSqlSet();
        assertTrue(sql != null && sql.replace(" ", "").contains("revision=COALESCE(revision,0)+1"));
    }

    @Test
    void incrementNullOrZeroRevisionMatchesNullAndIncrementsToOne() {
        Order order = order(0);
        order.setRevision(null);
        when(orderService.update(isNull(), any(Wrapper.class))).thenReturn(true);

        int next = service.increment(order, 0);

        assertEquals(1, next);
        assertEquals(1, order.getRevision());
        ArgumentCaptor<Wrapper> wrapper = ArgumentCaptor.forClass(Wrapper.class);
        verify(orderService).update(isNull(), wrapper.capture());
        String segment = wrapper.getValue().getCustomSqlSegment();
        assertTrue(segment.contains("IS NULL"));
    }

    @Test
    void incrementCasMissReturnsLatestConflict() {
        Order stale = order(7);
        Order latest = order(8);
        when(orderService.update(isNull(), any(Wrapper.class))).thenReturn(false);
        when(orderService.getById(stale.getId())).thenReturn(latest);

        ApiException ex = assertThrows(ApiException.class,
                () -> service.increment(stale, 7));

        assertEquals(409, ex.getHttpStatus());
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals(8, data.get("revision"));
    }

    private static Order order(int revision) {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD-REV-1");
        order.setShop_id(3);
        order.setRevision(revision);
        order.setTransac_status("unsettled");
        order.setSett_amount(108d);
        order.setDiscount_amount(8d);
        order.setService_fee(5d);
        return order;
    }
}
