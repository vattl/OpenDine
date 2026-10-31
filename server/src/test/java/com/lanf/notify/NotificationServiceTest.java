package com.lanf.notify;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.notify.entity.NotificationDelivery;
import com.lanf.notify.entity.NotificationRule;
import com.lanf.notify.mapper.NotificationDeliveryMapper;
import com.lanf.notify.mapper.NotificationRuleMapper;
import com.lanf.notify.service.NotificationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 通知模块单元测试：规则 CRUD、版本冲突 409、删除二次确认、试发脱敏、30 天窗口。
 */
class NotificationServiceTest {

    private NotificationService service;
    private NotificationRuleMapper ruleMapper;
    private NotificationDeliveryMapper deliveryMapper;

    @BeforeEach
    void setUp() {
        ruleMapper = mock(NotificationRuleMapper.class);
        deliveryMapper = mock(NotificationDeliveryMapper.class);
        service = new NotificationService();
        org.springframework.test.util.ReflectionTestUtils.setField(service, "ruleMapper", ruleMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "deliveryMapper", deliveryMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
    }

    private NotificationRule rule(long id, int version) {
        NotificationRule r = new NotificationRule();
        r.setId(id);
        r.setShop_id(1);
        r.setName("新订单通知");
        r.setEvent_type("order_new");
        r.setChannels_json("[\"app\"]");
        r.setRecipients_json("[{\"name\":\"张三\",\"phone\":\"13812341234\"}]");
        r.setVersion(version);
        r.setEnabled(1);
        return r;
    }

    @Test
    void createRuleAssignsVersionOne() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新订单通知");
        body.put("eventType", "order_new");
        body.put("channels", Collections.singletonList("app"));

        service.createRule(1, body, 7);

        verify(ruleMapper).insert(any(NotificationRule.class));
    }

    @Test
    void createRuleRejectsUnknownEventType() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "x");
        body.put("eventType", "not_a_type");
        ApiException ex = assertThrows(ApiException.class, () -> service.createRule(1, body, 7));
        assertEquals(400, ex.getHttpStatus());
    }

    @Test
    void updateRejectsStaleVersion() {
        when(ruleMapper.selectById(9L)).thenReturn(rule(9, 3));
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新名字");
        body.put("version", 1);
        ApiException ex = assertThrows(ApiException.class, () -> service.updateRule(1, 9, body, 7));
        assertEquals(409, ex.getHttpStatus());
        assertEquals(NotificationService.ERROR_VERSION_CONFLICT, ex.getErrorCode());
    }

    @Test
    void updateBumpsVersion() {
        when(ruleMapper.selectById(9L)).thenReturn(rule(9, 3));
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新名字");
        body.put("version", 3);
        Map<String, Object> result = service.updateRule(1, 9, body, 7);
        assertEquals(4, result.get("version"));
        assertEquals("新名字", result.get("name"));
    }

    @Test
    void deleteRequiresConfirm() {
        ApiException ex = assertThrows(ApiException.class, () -> service.deleteRule(1, 9, 3, false, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals(NotificationService.ERROR_CONFIRM_REQUIRED, ex.getErrorCode());
    }

    @Test
    void deleteRuleWithConfirmAndVersion() {
        when(ruleMapper.selectById(9L)).thenReturn(rule(9, 3));
        service.deleteRule(1, 9, 3, true, 7);
        verify(ruleMapper).deleteById(9L);
    }

    @Test
    void listRulesMasksRecipientPhone() {
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(9, 3)));
        Map<String, Object> result = service.listRules(1, null, 1, 20);
        List<Map<String, Object>> items = (List<Map<String, Object>>) result.get("items");
        List<Map<String, Object>> recipients = (List<Map<String, Object>>) items.get(0).get("recipients");
        assertEquals("138****1234", recipients.get(0).get("phone"));
    }

    @Test
    void testDeliveryMasksRecipient() {
        when(ruleMapper.selectById(9L)).thenReturn(rule(9, 3));
        Map<String, Object> result = service.testDelivery(1, 9, null, 7);
        verify(deliveryMapper).insert(any(NotificationDelivery.class));
        List<Map<String, Object>> deliveries = (List<Map<String, Object>>) result.get("deliveries");
        assertFalse(String.valueOf(deliveries.get(0).get("recipient")).contains("12341234"));
        assertEquals("SENT", result.get("status"));
    }

    @Test
    void deliveriesRejectRangeBeforeOnlineWindow() {
        ApiException ex = assertThrows(ApiException.class, () -> service.listDeliveries(
                1, null, null, null, "2020-01-01 00:00:00", "2020-02-01 00:00:00", 1, 20));
        assertEquals(400, ex.getHttpStatus());
        assertEquals(NotificationService.ERROR_ARCHIVED_ONLY, ex.getErrorCode());
    }

    @Test
    void deliveriesReturnWithinWindow() {
        when(deliveryMapper.selectList(any())).thenReturn(Collections.emptyList());
        Map<String, Object> result = service.listDeliveries(1, null, null, null, null, null, 1, 20);
        assertEquals(30, result.get("onlineWindowDays"));
        assertEquals(0, result.get("total"));
    }
}
