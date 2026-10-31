package com.lanf.notify;

import com.lanf.controller.WechatSubscribeController;
import com.lanf.controller.admin.AdminSubscribeConfigController;
import com.lanf.entity.R;
import com.lanf.entity.SubscribeSceneTemplate;
import com.lanf.entity.SubscribeSendLog;
import com.lanf.entity.UserSubscribeQuota;
import com.lanf.mapper.SubscribeSceneTemplateMapper;
import com.lanf.mapper.SubscribeSendLogMapper;
import com.lanf.mapper.UserSubscribeQuotaMapper;
import com.lanf.service.impl.WechatSubscribeQuotaServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class WechatSubscribeControllableQuotaTest {

    private WechatSubscribeQuotaServiceImpl quotaService;
    private SubscribeSceneTemplateMapper sceneTemplateMapper;
    private UserSubscribeQuotaMapper quotaMapper;
    private SubscribeSendLogMapper sendLogMapper;

    private WechatSubscribeController cController;
    private AdminSubscribeConfigController adminController;

    @BeforeEach
    public void setup() {
        quotaService = new WechatSubscribeQuotaServiceImpl();
        sceneTemplateMapper = mock(SubscribeSceneTemplateMapper.class);
        quotaMapper = mock(UserSubscribeQuotaMapper.class);
        sendLogMapper = mock(SubscribeSendLogMapper.class);

        ReflectionTestUtils.setField(quotaService, "sceneTemplateMapper", sceneTemplateMapper);
        ReflectionTestUtils.setField(quotaService, "quotaMapper", quotaMapper);
        ReflectionTestUtils.setField(quotaService, "sendLogMapper", sendLogMapper);

        cController = new WechatSubscribeController();
        ReflectionTestUtils.setField(cController, "subscribeQuotaService", quotaService);

        adminController = new AdminSubscribeConfigController();
        ReflectionTestUtils.setField(adminController, "subscribeQuotaService", quotaService);
    }

    @Test
    public void testPromptDecision_noQuota_needsPrompt() {
        SubscribeSceneTemplate template = new SubscribeSceneTemplate();
        template.setScene_code("ORDER_PICKUP");
        template.setTemplate_id("TMPL_PICKUP_001");
        template.setTitle("取餐通知");
        template.setIs_active(1);

        when(sceneTemplateMapper.selectList(any())).thenReturn(Collections.singletonList(template));
        when(quotaMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> decision = quotaService.getPromptDecision("test_openid_123", "ORDER_PICKUP");

        assertTrue((Boolean) decision.get("need_prompt"));
        List<?> tmplIds = (List<?>) decision.get("tmpl_ids");
        assertEquals(1, tmplIds.size());
        assertEquals("TMPL_PICKUP_001", tmplIds.get(0));

        R controllerRes = cController.getPromptDecision("test_openid_123", "ORDER_PICKUP");
        assertEquals(0, controllerRes.get("code"));
    }

    @Test
    public void testPromptDecision_hasQuota_noPromptNeeded() {
        SubscribeSceneTemplate template = new SubscribeSceneTemplate();
        template.setScene_code("ORDER_PICKUP");
        template.setTemplate_id("TMPL_PICKUP_001");
        template.setTitle("取餐通知");
        template.setIs_active(1);

        UserSubscribeQuota userQuota = new UserSubscribeQuota();
        userQuota.setOpenid("test_openid_123");
        userQuota.setScene_code("ORDER_PICKUP");
        userQuota.setTemplate_id("TMPL_PICKUP_001");
        userQuota.setAvailable_quota(2);
        userQuota.setBan_status(0);

        when(sceneTemplateMapper.selectList(any())).thenReturn(Collections.singletonList(template));
        when(quotaMapper.selectList(any())).thenReturn(Collections.singletonList(userQuota));

        Map<String, Object> decision = quotaService.getPromptDecision("test_openid_123", "ORDER_PICKUP");

        assertFalse((Boolean) decision.get("need_prompt"));
        List<?> tmplIds = (List<?>) decision.get("tmpl_ids");
        assertTrue(tmplIds.isEmpty());
    }

    @Test
    public void testPromptDecision_userBanned_noPrompt() {
        SubscribeSceneTemplate template = new SubscribeSceneTemplate();
        template.setScene_code("ORDER_PICKUP");
        template.setTemplate_id("TMPL_PICKUP_001");
        template.setTitle("取餐通知");
        template.setIs_active(1);

        UserSubscribeQuota userQuota = new UserSubscribeQuota();
        userQuota.setOpenid("test_openid_123");
        userQuota.setScene_code("ORDER_PICKUP");
        userQuota.setTemplate_id("TMPL_PICKUP_001");
        userQuota.setAvailable_quota(0);
        userQuota.setBan_status(1);

        when(sceneTemplateMapper.selectList(any())).thenReturn(Collections.singletonList(template));
        when(quotaMapper.selectList(any())).thenReturn(Collections.singletonList(userQuota));

        Map<String, Object> decision = quotaService.getPromptDecision("test_openid_123", "ORDER_PICKUP");

        assertFalse((Boolean) decision.get("need_prompt"));
    }

    @Test
    public void testReportAuthResult_acceptAndReject() {
        Map<String, String> results = new HashMap<>();
        results.put("TMPL_PICKUP_001", "accept");
        results.put("TMPL_STATUS_002", "reject");

        Map<String, Object> reportRes = quotaService.reportAuthResult("test_openid_123", "ORDER_PICKUP", results);

        assertEquals("SUCCESS", reportRes.get("status"));
        assertEquals(1, reportRes.get("accepted"));
        assertEquals(1, reportRes.get("rejected"));

        verify(quotaMapper, times(1)).recordAccept("test_openid_123", "ORDER_PICKUP", "TMPL_PICKUP_001");
        verify(quotaMapper, times(1)).recordReject("test_openid_123", "ORDER_PICKUP", "TMPL_STATUS_002", 0);
    }

    @Test
    public void testHandleSendResult_success_decrementsQuotaAndAudits() {
        UserSubscribeQuota cur = new UserSubscribeQuota();
        cur.setOpenid("test_openid_123");
        cur.setScene_code("ORDER_PICKUP");
        cur.setAvailable_quota(3);

        when(quotaMapper.selectOne(any())).thenReturn(cur);

        quotaService.handleSendResult("test_openid_123", "ORDER_PICKUP", "TMPL_PICKUP_001",
                0, "ok", "ORD_20261031_001", 120L, "pickupCode=101");

        verify(quotaMapper, times(1)).decrementQuota("test_openid_123", "ORDER_PICKUP");

        ArgumentCaptor<SubscribeSendLog> logCaptor = ArgumentCaptor.forClass(SubscribeSendLog.class);
        verify(sendLogMapper, times(1)).insert(logCaptor.capture());

        SubscribeSendLog captured = logCaptor.getValue();
        assertEquals("ORD_20261031_001", captured.getBiz_no());
        assertEquals("SUCCESS", captured.getSend_status());
        assertEquals(0, captured.getErrcode());
        assertEquals(3, captured.getQuota_before());
        assertEquals(2, captured.getQuota_after());
    }

    @Test
    public void testHandleSendResult_43101_autoResetsQuotaToZero() {
        UserSubscribeQuota cur = new UserSubscribeQuota();
        cur.setOpenid("test_openid_123");
        cur.setScene_code("ORDER_PICKUP");
        cur.setAvailable_quota(2);

        when(quotaMapper.selectOne(any())).thenReturn(cur);

        quotaService.handleSendResult("test_openid_123", "ORDER_PICKUP", "TMPL_PICKUP_001",
                43101, "user refuse to accept the msg", "ORD_20261031_002", 95L, "pickupCode=102");

        verify(quotaMapper, times(1)).resetQuotaToZero("test_openid_123", "ORDER_PICKUP");

        ArgumentCaptor<SubscribeSendLog> logCaptor = ArgumentCaptor.forClass(SubscribeSendLog.class);
        verify(sendLogMapper, times(1)).insert(logCaptor.capture());

        SubscribeSendLog captured = logCaptor.getValue();
        assertEquals("FAILED", captured.getSend_status());
        assertEquals(43101, captured.getErrcode());
        assertEquals(2, captured.getQuota_before());
        assertEquals(0, captured.getQuota_after());
    }

    @Test
    public void testAdminController_endpoints() {
        SubscribeSceneTemplate template = new SubscribeSceneTemplate();
        template.setScene_code("ORDER_PICKUP");
        template.setTemplate_id("TMPL_PICKUP_001");
        template.setTitle("取餐通知");

        when(sceneTemplateMapper.selectList(any())).thenReturn(Collections.singletonList(template));
        when(sceneTemplateMapper.selectOne(any())).thenReturn(template);
        when(sceneTemplateMapper.updateById(any())).thenReturn(1);

        R scenesRes = adminController.listScenes();
        assertEquals(0, scenesRes.get("code"));

        R updateRes = adminController.updateScene("ORDER_PICKUP", template);
        assertEquals(0, updateRes.get("code"));

        when(sendLogMapper.selectList(any())).thenReturn(Collections.emptyList());
        R logsRes = adminController.listLogs("ORD001", null, null, null, 10);
        assertEquals(0, logsRes.get("code"));
    }
}
