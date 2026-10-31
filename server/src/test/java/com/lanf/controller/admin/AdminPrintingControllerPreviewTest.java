package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.printing.model.PrintPreviewResult;
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

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
public class AdminPrintingControllerPreviewTest {

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
    void testPreviewPost() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("scenario", "ORDER");
        body.put("paperSize", "80mm");

        PrintPreviewResult expected = new PrintPreviewResult();
        expected.setScenario("ORDER");
        expected.setPaperSize("80mm");

        when(printingService.previewPrint(eq(1), any())).thenReturn(expected);

        R r = controller.previewPrintPost(body);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals("预览生成成功", r.get("msg"));
        assertEquals(expected, r.get("data"));
    }

    @Test
    void testPreviewGet() {
        PrintPreviewResult expected = new PrintPreviewResult();
        expected.setScenario("KITCHEN");
        expected.setPaperSize("58mm");

        when(printingService.previewPrint(eq(1), any())).thenReturn(expected);

        R r = controller.previewPrintGet("KITCHEN", 101L, "DD001", 2L, "58mm", false);
        assertNotNull(r);
        assertEquals(0, r.get("code"));
        assertEquals("预览生成成功", r.get("msg"));
        assertEquals(expected, r.get("data"));
    }
}
