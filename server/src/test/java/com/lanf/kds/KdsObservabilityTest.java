package com.lanf.kds;

import com.lanf.kds.interceptor.KdsDeviceAuthInterceptor;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.service.KdsMetricsService;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

public class KdsObservabilityTest {

    @Test
    public void testKdsMetricsServiceCommandAndWsMetrics() {
        KdsMetricsService service = new KdsMetricsService();

        // 1. Record command executions
        service.recordCommandExecution(1, "cook", 200, 50);
        service.recordCommandExecution(1, "cook", 200, 100);
        service.recordCommandExecution(1, "cook", 409, 30);
        service.recordCommandExecution(1, "cook", 400, 20);
        service.recordCommandExecution(1, "cook", 500, 200);

        // 2. Record traffic
        service.recordBootstrapRequest(1);
        service.recordBusinessDayRequest(1);
        service.recordChangesRequest(1);
        service.recordChangesRequest(1);

        // 3. Record websocket
        service.recordWsDispatched(10);
        service.recordWsAcknowledged();
        service.recordWsAcknowledged();
        service.recordWsDisconnect("slow_consumer");

        Map<String, Object> snapshot = service.getMetricsSnapshot();
        Assertions.assertNotNull(snapshot);

        @SuppressWarnings("unchecked")
        Map<String, Object> commands = (Map<String, Object>) snapshot.get("commands");
        Assertions.assertEquals(5L, commands.get("total_count"));
        Assertions.assertEquals(2L, commands.get("success_count"));
        Assertions.assertEquals(1L, commands.get("conflict_count"));
        Assertions.assertEquals(1L, commands.get("rejected_count"));
        Assertions.assertEquals(1L, commands.get("error_count"));
        Assertions.assertEquals(0.2, (Double) commands.get("conflict_rate"), 0.001);

        @SuppressWarnings("unchecked")
        Map<String, Object> latency = (Map<String, Object>) commands.get("latency");
        Assertions.assertEquals(80.0, (Double) latency.get("avg_ms"), 0.001);
        Assertions.assertEquals(200L, latency.get("max_ms"));
        Assertions.assertEquals(20L, latency.get("min_ms"));

        @SuppressWarnings("unchecked")
        Map<String, Object> ws = (Map<String, Object>) snapshot.get("websocket");
        Assertions.assertEquals(10L, ws.get("dispatched_frames"));
        Assertions.assertEquals(2L, ws.get("acknowledged_frames"));
        Assertions.assertEquals(0.2, (Double) ws.get("ack_rate"), 0.001);

        @SuppressWarnings("unchecked")
        Map<String, Long> disconnects = (Map<String, Long>) ws.get("disconnect_reasons");
        Assertions.assertEquals(1L, disconnects.get("slow_consumer"));

        @SuppressWarnings("unchecked")
        Map<String, Object> traffic = (Map<String, Object>) snapshot.get("traffic");
        Assertions.assertEquals(1L, traffic.get("bootstrap_requests"));
        Assertions.assertEquals(1L, traffic.get("business_day_requests"));
        Assertions.assertEquals(2L, traffic.get("changes_requests"));
        Assertions.assertEquals(1.0, (Double) traffic.get("snapshot_to_changes_ratio"), 0.001);
    }

    @Test
    public void testKdsDeviceAuthInterceptorHeaderCorrelationAndMdc() throws Exception {
        KdsDeviceAuthInterceptor interceptor = new KdsDeviceAuthInterceptor();
        KdsDeviceService deviceService = Mockito.mock(KdsDeviceService.class);
        ReflectionTestUtils.setField(interceptor, "deviceService", deviceService);

        KdsDevice mockDevice = new KdsDevice();
        mockDevice.setShop_id(88);
        mockDevice.setDevice_code("DEV-001");
        Mockito.when(deviceService.findByToken("test-token")).thenReturn(mockDevice);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setRequestURI("/kds/v2/commands");
        request.setServletPath("/kds/v2/commands");
        request.addHeader("X-Kds-Device-Token", "test-token");
        request.addHeader("X-Request-Id", "req-12345");
        request.addHeader("X-KDS-Command-Id", "cmd-9999");
        request.addHeader("X-KDS-Device-Code", "DEV-001");

        MockHttpServletResponse response = new MockHttpServletResponse();

        boolean allowed = interceptor.preHandle(request, response, new Object());
        Assertions.assertTrue(allowed);

        // Verify response header
        Assertions.assertEquals("req-12345", response.getHeader("X-Request-Id"));

        // Verify MDC
        Assertions.assertEquals("req-12345", MDC.get("requestId"));
        Assertions.assertEquals("cmd-9999", MDC.get("commandId"));
        Assertions.assertEquals("DEV-001", MDC.get("deviceCode"));

        // Verify cleanup
        interceptor.afterCompletion(request, response, new Object(), null);
        Assertions.assertNull(MDC.get("requestId"));
        Assertions.assertNull(MDC.get("commandId"));
        Assertions.assertNull(MDC.get("deviceCode"));
    }
}
