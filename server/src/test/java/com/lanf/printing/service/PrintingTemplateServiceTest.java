package com.lanf.printing.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.engine.PrintTemplateEngineImpl;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.entity.PrintingTemplate;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.mapper.PrintingTemplateMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class PrintingTemplateServiceTest {

    @InjectMocks
    private PrintingService printingService;

    @Mock
    private PrintingTemplateMapper templateMapper;

    @Mock
    private PrintingRuleMapper ruleMapper;

    @Mock
    private PrintingDeviceMapper deviceMapper;

    @Mock
    private PrintingJobMapper jobMapper;

    @Spy
    private ObjectMapper objectMapper = new ObjectMapper();

    @Spy
    private PrintTemplateEngine printTemplateEngine = new PrintTemplateEngineImpl();

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(printingService, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(printingService, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(printingService, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(printingService, "objectMapper", objectMapper);
        ReflectionTestUtils.setField(printingService, "printTemplateEngine", printTemplateEngine);
    }

    @Test
    void testGetTemplates() {
        PrintingTemplate t1 = new PrintingTemplate();
        t1.setId(1L);
        t1.setShop_id(1);
        t1.setTemplate_code("tpl_custom_001");
        t1.setTemplate_name("自定义结账单");
        t1.setScenario("ORDER");
        t1.setPaper_size("58mm");
        t1.setIs_system(0);
        t1.setIs_default(1);
        t1.setVersion(1);

        when(templateMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(t1));

        List<Map<String, Object>> templates = printingService.getTemplates(1, "ORDER", "58mm");
        assertNotNull(templates);
        assertEquals(1, templates.size());
        assertEquals("tpl_custom_001", templates.get(0).get("templateCode"));
        assertEquals("自定义结账单", templates.get(0).get("templateName"));
    }

    @Test
    void testCreateTemplate() {
        when(templateMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);
        when(templateMapper.insert(any(PrintingTemplate.class))).thenAnswer(inv -> {
            PrintingTemplate pt = inv.getArgument(0);
            pt.setId(10L);
            return 1;
        });

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("templateName", "新结账小票");
        body.put("scenario", "ORDER");
        body.put("paperSize", "58mm");
        body.put("templateCode", "tpl_order_new");
        body.put("isDefault", true);

        Map<String, Object> created = printingService.createTemplate(1, body, 99);
        assertNotNull(created);
        assertEquals("tpl_order_new", created.get("templateCode"));
        assertEquals(1, created.get("version"));
        assertTrue((Boolean) created.get("isDefault"));

        ArgumentCaptor<PrintingTemplate> captor = ArgumentCaptor.forClass(PrintingTemplate.class);
        verify(templateMapper).insert(captor.capture());
        assertEquals("CHECKOUT", captor.getValue().getScenario());
    }

    @Test
    void testCreateTemplateAcceptsValidCustomScenarioCode() {
        when(templateMapper.selectCount(any(QueryWrapper.class))).thenReturn(0);
        when(templateMapper.insert(any(PrintingTemplate.class))).thenReturn(1);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("templateName", "自提提醒单");
        body.put("scenario", "pickup_notice");

        printingService.createTemplate(1, body, 99);

        ArgumentCaptor<PrintingTemplate> captor = ArgumentCaptor.forClass(PrintingTemplate.class);
        verify(templateMapper).insert(captor.capture());
        assertEquals("PICKUP_NOTICE", captor.getValue().getScenario());
    }

    @Test
    void testUpdateTemplateVersionConflict() {
        PrintingTemplate existing = new PrintingTemplate();
        existing.setId(5L);
        existing.setShop_id(1);
        existing.setTemplate_code("tpl_order_custom");
        existing.setVersion(3);
        existing.setIs_system(0);

        when(templateMapper.selectById(5L)).thenReturn(existing);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("templateName", "修改后的名称");
        body.put("version", 2); // 冲突版本

        ApiException ex = assertThrows(ApiException.class, () -> {
            printingService.updateTemplate(1, 5L, body, 99);
        });
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_VERSION_CONFLICT", ex.getErrorCode());
    }

    @Test
    void testUpdateTemplatePersistsCanonicalScenario() {
        PrintingTemplate existing = new PrintingTemplate();
        existing.setId(5L);
        existing.setShop_id(1);
        existing.setTemplate_code("tpl_checkout_custom");
        existing.setTemplate_name("结账单");
        existing.setScenario("CHECKOUT");
        existing.setVersion(3);
        existing.setIs_system(0);
        existing.setIs_default(0);

        when(templateMapper.selectById(5L)).thenReturn(existing);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 3);
        body.put("scenario", "serve");

        printingService.updateTemplate(1, 5L, body, 99);

        ArgumentCaptor<PrintingTemplate> captor = ArgumentCaptor.forClass(PrintingTemplate.class);
        verify(templateMapper).updateById(captor.capture());
        assertEquals("EXPEDITE", captor.getValue().getScenario());
    }

    @Test
    void testSaveRulesAllowsTemplateFromAnotherScenario() {
        PrintingDevice device = new PrintingDevice();
        device.setId(101L);
        device.setShop_id(1);
        when(deviceMapper.selectById(101L)).thenReturn(device);
        PrintingTemplate template = new PrintingTemplate();
        template.setId(8L);
        template.setShop_id(1);
        template.setTemplate_code("tpl_checkout_custom");
        template.setScenario("CHECKOUT");
        when(templateMapper.selectOne(any(QueryWrapper.class))).thenReturn(template);

        Map<String, Object> rule = new LinkedHashMap<>();
        rule.put("scenario", "kitchen");
        rule.put("deviceId", 101);
        rule.put("templateCode", "tpl_checkout_custom");
        rule.put("copies", 1);
        rule.put("enabled", true);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 0);
        body.put("rules", Collections.singletonList(rule));

        when(ruleMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        Map<String, Object> saved = printingService.saveRules(1, body, 99);

        assertNotNull(saved);
        verify(ruleMapper).insert(argThat(savedRule ->
                "kitchen".equals(savedRule.getScenario()) &&
                        "tpl_checkout_custom".equals(savedRule.getTemplate_code())));
    }

    @Test
    void testDeleteTemplateInUseByRuleThrowsException() {
        PrintingTemplate pt = new PrintingTemplate();
        pt.setId(8L);
        pt.setShop_id(1);
        pt.setTemplate_code("tpl_active_rule");
        pt.setIs_system(0);

        when(templateMapper.selectById(8L)).thenReturn(pt);

        PrintingRule rule = new PrintingRule();
        rule.setId(101L);
        rule.setShop_id(1);
        rule.setScenario("ORDER");
        rule.setTemplate_code("tpl_active_rule");

        when(ruleMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(rule));

        ApiException ex = assertThrows(ApiException.class, () -> {
            printingService.deleteTemplate(1, 8L, 99);
        });
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINT_TEMPLATE_IN_USE_BY_RULE", ex.getErrorCode());
    }

    @Test
    void testGetTemplateMeta() {
        Map<String, Object> meta = printingService.getTemplateMeta();
        assertNotNull(meta);
        assertTrue(meta.containsKey("scenarios"));
        assertTrue(meta.containsKey("parametersByScenario"));

        List<Map<String, Object>> scenarios = (List<Map<String, Object>>) meta.get("scenarios");
        assertTrue(scenarios.stream().anyMatch(s -> "SHIFT".equals(s.get("code"))));
        assertTrue(scenarios.stream().anyMatch(s -> "REFUND".equals(s.get("code"))));
        assertTrue(scenarios.stream().anyMatch(s -> "LABEL".equals(s.get("code"))));
        assertTrue(scenarios.stream().anyMatch(s -> "FULL_ORDER".equals(s.get("code"))));
        assertTrue(scenarios.stream().anyMatch(s -> "TAKEOUT".equals(s.get("code"))));
        assertTrue(scenarios.stream().anyMatch(s -> "PACKING".equals(s.get("code"))));

        Map<String, List<Map<String, Object>>> params = (Map<String, List<Map<String, Object>>>) meta.get("parametersByScenario");
        assertNotNull(params.get("SHIFT"));
        assertNotNull(params.get("REFUND"));
        assertNotNull(params.get("LABEL"));
        assertNotNull(params.get("FULL_ORDER"));
        assertNotNull(params.get("TAKEOUT"));
        assertNotNull(params.get("PACKING"));
    }
}
