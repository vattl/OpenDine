package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.printing.service.PrintingService;
import com.lanf.security.SecurityAuditService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
public class AdminPrintingControllerTemplateTest {

    @Mock
    private PrintingService printingService;
    @Mock
    private SecurityAuditService securityAuditService;

    @InjectMocks
    private AdminPrintingController controller;

    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 1);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 99);
        ReflectionTestUtils.setField(controller, "currentRequest", request);
    }

    @Test
    void testListTemplates() {
        Map<String, Object> t = new LinkedHashMap<>();
        t.put("id", 1L);
        t.put("templateCode", "tpl_order_def");
        t.put("templateName", "标准结账单");

        when(printingService.getTemplates(eq(1), eq("ORDER"), eq("58mm")))
                .thenReturn(Collections.singletonList(t));

        R r = controller.listTemplates("ORDER", "58mm");
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals(1, r.get("shopId"));
        assertEquals(Collections.singletonList(t), r.get("templates"));
    }

    @Test
    void testGetTemplateDetail() {
        Map<String, Object> t = new LinkedHashMap<>();
        t.put("id", 5L);
        t.put("templateCode", "tpl_test");
        t.put("templateJson", "{\"blocks\":[]}");

        when(printingService.getTemplateById(eq(1), eq(5L))).thenReturn(t);

        R r = controller.getTemplateDetail(5L);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals(t, r.get("template"));
    }

    @Test
    void testCreateTemplate() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("templateName", "测试创建");
        body.put("scenario", "ORDER");

        Map<String, Object> created = new LinkedHashMap<>();
        created.put("id", 10L);
        created.put("version", 1);

        when(printingService.createTemplate(eq(1), any(), eq(99))).thenReturn(created);

        R r = controller.createTemplate(body);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals(1, r.get("version"));
    }

    @Test
    void testUpdateTemplate() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("templateName", "测试更新");

        Map<String, Object> updated = new LinkedHashMap<>();
        updated.put("id", 10L);
        updated.put("version", 2);

        when(printingService.updateTemplate(eq(1), eq(10L), any(), eq(99))).thenReturn(updated);

        R r = controller.updateTemplate(10L, body);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals(2, r.get("version"));
    }

    @Test
    void testDeleteTemplate() {
        doNothing().when(printingService).deleteTemplate(eq(1), eq(10L), eq(99));

        R r = controller.deleteTemplate(10L);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals("模板删除成功", r.get("msg"));
    }

    @Test
    void testSetDefaultTemplate() {
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("id", 10L);
        res.put("isDefault", true);

        when(printingService.setDefaultTemplate(eq(1), eq(10L), eq(99))).thenReturn(res);

        R r = controller.setDefaultTemplate(10L);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals("已设为默认模板", r.get("msg"));
    }
}
