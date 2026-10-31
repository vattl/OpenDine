package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.kds.replication.KdsReplicationEventRequest;
import com.lanf.kds.replication.KdsReplicationOutcome;
import com.lanf.kds.replication.KdsReplicationService;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;

import java.util.Collections;
import java.util.Arrays;
import java.util.Map;
import com.lanf.kds.replication.KdsReplicationBatchRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

class AdminKdsReplicationControllerTest {

    @Test
    void passesInterceptorResolvedShopAndReturnsStableAck() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest event = new KdsReplicationEventRequest();
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(eq(7), eq(event), eq(request))).thenReturn(KdsReplicationOutcome.ok(
                Collections.singletonMap("event_id", "e1")));

        ResponseEntity<R> response = new AdminKdsReplicationController(service).accept(event, request);

        assertEquals(200, response.getStatusCodeValue());
        assertEquals(0, response.getBody().get("code"));
        verify(service).accept(7, event, request);
    }

    @Test
    void preservesRetryClassificationInHttpAndBusinessCodes() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest event = new KdsReplicationEventRequest();
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(eq(7), eq(event), eq(request))).thenReturn(
                KdsReplicationOutcome.pending("mapping pending", Collections.singletonMap("event_id", "e1")));

        ResponseEntity<R> response = new AdminKdsReplicationController(service).accept(event, request);

        assertEquals(409, response.getStatusCodeValue());
        assertEquals(4090, response.getBody().get("code"));
        assertEquals("mapping pending", response.getBody().get("msg"));
    }

    @Test
    void distinguishesPermanentPayloadErrorsFromTemporaryCloudFailures() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest invalidEvent = new KdsReplicationEventRequest();
        KdsReplicationEventRequest temporaryEvent = new KdsReplicationEventRequest();
        invalidEvent.setEventId("invalid");
        temporaryEvent.setEventId("temporary");
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(7, invalidEvent, request)).thenReturn(
                KdsReplicationOutcome.invalid("invalid payload"));
        when(service.accept(7, temporaryEvent, request)).thenReturn(
                KdsReplicationOutcome.failure("temporary cloud failure"));
        AdminKdsReplicationController controller = new AdminKdsReplicationController(service);

        ResponseEntity<R> invalid = controller.accept(invalidEvent, request);
        ResponseEntity<R> temporary = controller.accept(temporaryEvent, request);

        assertEquals(400, invalid.getStatusCodeValue());
        assertEquals(4000, invalid.getBody().get("code"));
        assertEquals(500, temporary.getStatusCodeValue());
        assertEquals(5000, temporary.getBody().get("code"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void batchKeepsInputOrderAndClassifiesEachAck() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest first = new KdsReplicationEventRequest();
        KdsReplicationEventRequest second = new KdsReplicationEventRequest();
        first.setEventId("e1");
        second.setEventId("e2");
        KdsReplicationBatchRequest batch = new KdsReplicationBatchRequest();
        batch.setEvents(Arrays.asList(first, second));
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(7, first, request)).thenReturn(KdsReplicationOutcome.ok(Collections.singletonMap("event_id", "e1")));
        when(service.accept(7, second, request)).thenReturn(KdsReplicationOutcome.pending("mapping", Collections.singletonMap("event_id", "e2")));

        ResponseEntity<R> response = new AdminKdsReplicationController(service).acceptBatch(batch, request);

        Map<String, Object> data = (Map<String, Object>) response.getBody().get("data");
        java.util.List<Map<String, Object>> results = (java.util.List<Map<String, Object>>) data.get("results");
        assertEquals("e1", results.get(0).get("event_id"));
        assertEquals("e2", results.get(1).get("event_id"));
        assertEquals(1, data.get("accepted"));
        assertEquals(1, data.get("failed"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void oneUnexpectedBatchItemFailureDoesNotPreventLaterAck() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest first = new KdsReplicationEventRequest();
        KdsReplicationEventRequest second = new KdsReplicationEventRequest();
        first.setEventId("broken");
        second.setEventId("good");
        KdsReplicationBatchRequest batch = new KdsReplicationBatchRequest();
        batch.setEvents(Arrays.asList(first, second));
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(7, first, request)).thenThrow(new IllegalStateException("boom"));
        when(service.accept(7, second, request)).thenReturn(KdsReplicationOutcome.ok(Collections.singletonMap("event_id", "good")));

        ResponseEntity<R> response = new AdminKdsReplicationController(service).acceptBatch(batch, request);

        Map<String, Object> data = (Map<String, Object>) response.getBody().get("data");
        java.util.List<Map<String, Object>> results = (java.util.List<Map<String, Object>>) data.get("results");
        assertEquals(5000, results.get(0).get("code"));
        assertEquals(0, results.get(1).get("code"));
        verify(service).accept(7, second, request);
    }

    @Test
    @SuppressWarnings("unchecked")
    void batchBlocksLaterEventsForFailedAggregateButContinuesOtherAggregates() {
        KdsReplicationService service = mock(KdsReplicationService.class);
        KdsReplicationEventRequest pending = event("e1", "order:10");
        KdsReplicationEventRequest blocked = event("e2", "order:10");
        KdsReplicationEventRequest independent = event("e3", "order:11");
        KdsReplicationBatchRequest batch = new KdsReplicationBatchRequest();
        batch.setEvents(Arrays.asList(pending, blocked, independent));
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);
        when(service.accept(7, pending, request)).thenReturn(
                KdsReplicationOutcome.pending("mapping", Collections.singletonMap("event_id", "e1")));
        when(service.accept(7, independent, request)).thenReturn(
                KdsReplicationOutcome.ok(Collections.singletonMap("event_id", "e3")));

        ResponseEntity<R> response = new AdminKdsReplicationController(service).acceptBatch(batch, request);

        Map<String, Object> data = (Map<String, Object>) response.getBody().get("data");
        java.util.List<Map<String, Object>> results = (java.util.List<Map<String, Object>>) data.get("results");
        assertEquals(4090, results.get(0).get("code"));
        assertEquals(4092, results.get(1).get("code"));
        assertEquals(true, ((Map<String, Object>) results.get(1).get("data")).get("blocked"));
        assertEquals(0, results.get(2).get("code"));
        verify(service, never()).accept(7, blocked, request);
        verify(service).accept(7, independent, request);
    }

    private static KdsReplicationEventRequest event(String eventId, String aggregateKey) {
        KdsReplicationEventRequest event = new KdsReplicationEventRequest();
        event.setEventId(eventId);
        event.setAggregateKey(aggregateKey);
        return event;
    }
}
