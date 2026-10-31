package com.lanf.printing.service;

import com.lanf.entity.Order;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingJob;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.entity.PrintingTemplate;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.mapper.PrintingTemplateMapper;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintResolvedPreview;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.printing.service.impl.PrintDispatcherServiceImpl;
import com.lanf.service.IFeieyunService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D002 精确打印预览一致性 — 派发器只读解析回归测试。
 *
 * <p>验收线：{@code previewExact} 复用真实派发的规则/设备/模板/渲染器选择，解析出的
 * 小票内容与 {@code dispatch} 逐字一致；只读执行，不插入任何 {@code t_printing_job}
 * 记录、不调用云打印；无样例回退与人工业务覆盖。
 */
class PrintExactPreviewParityTest {

    private PrintDispatcherServiceImpl dispatcher;
    private PrintingDeviceMapper deviceMapper;
    private PrintingRuleMapper ruleMapper;
    private PrintingJobMapper jobMapper;
    private PrintingTemplateMapper templateMapper;
    private IFeieyunService feieyunService;
    private PrintTemplateEngine templateEngine;

    @BeforeEach
    void setUp() {
        deviceMapper = mock(PrintingDeviceMapper.class);
        ruleMapper = mock(PrintingRuleMapper.class);
        jobMapper = mock(PrintingJobMapper.class);
        templateMapper = mock(PrintingTemplateMapper.class);
        feieyunService = mock(IFeieyunService.class);
        templateEngine = mock(PrintTemplateEngine.class);

        dispatcher = new PrintDispatcherServiceImpl();
        ReflectionTestUtils.setField(dispatcher, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(dispatcher, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(dispatcher, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(dispatcher, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(dispatcher, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(dispatcher, "templateEngine", templateEngine);
    }

    private static Order successOrder(int id, int shopId) {
        Order o = new Order();
        o.setId(id);
        o.setShop_id(shopId);
        o.setTransac_status("success");
        return o;
    }

    private PrintingDevice cloudDevice(long id, int shopId, String sn) {
        PrintingDevice d = new PrintingDevice();
        d.setId(id);
        d.setShop_id(shopId);
        d.setName("前台飞鹅打印机");
        d.setTransport("CLOUD");
        d.setBrand("飞鹅");
        d.setConnection_json("{\"sn\":\"" + sn + "\",\"user\":\"feie_user_1\",\"ukey\":\"key123\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}");
        d.setStatus("ONLINE");
        return d;
    }

    private PrintingDevice lanDevice(long id, int shopId) {
        PrintingDevice d = new PrintingDevice();
        d.setId(id);
        d.setShop_id(shopId);
        d.setName("后厨网口打印机");
        d.setTransport("LAN");
        d.setBrand("爱普生");
        d.setConnection_json("{\"ip\":\"192.168.1.200\",\"port\":9100}");
        d.setStatus("ONLINE");
        return d;
    }

    private PrintingRule rule(long id, int shopId, String scenario, long deviceId, int copies) {
        PrintingRule r = new PrintingRule();
        r.setId(id);
        r.setShop_id(shopId);
        r.setScenario(scenario);
        r.setDevice_id(deviceId);
        r.setCopies(copies);
        r.setEnabled(1);
        return r;
    }

    private PrintingTemplate createMockTemplate(String scenario) {
        PrintingTemplate pt = new PrintingTemplate();
        pt.setId(101L);
        pt.setShop_id(0);
        pt.setScenario(scenario);
        pt.setTemplate_code("tpl_sys_" + scenario.toLowerCase());
        pt.setTemplate_name("系统默认模板");
        pt.setTemplate_json("{\"scenario\":\"" + scenario + "\",\"blocks\":[]}");
        return pt;
    }

    private void stubOrderRender() {
        when(templateEngine.parseDsl(anyString())).thenReturn(new PrintTemplateDsl());
        when(templateEngine.renderDynamicTicket(any(), any(), any())).thenReturn("<CB>结账单</CB><BR>合计: 88.00");
    }

    @Test
    void exactPreviewContentMatchesDispatchPayloadAndLeavesZeroJobSideEffects() throws Exception {
        PrintingRule rule = rule(1L, 1, "order", 10L, 1);
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("ORDER"));
        stubOrderRender();
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(501L);
            return 1;
        });
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt())).thenReturn("{\"ret\":0}");

        Order order = successOrder(100, 1);
        PrintContext ctx = PrintContext.ofOrder(order, false);

        // 1. 真实派发：产生一次渲染、一条打印任务、一次云调用
        List<PrintDispatchResult> dispatched = dispatcher.dispatch(1, PrintScenario.ORDER, ctx);
        assertEquals(1, dispatched.size());
        String dispatchPayload = dispatched.get(0).getPayloadText();
        assertEquals("<CB>结账单</CB><BR>合计: 88.00", dispatchPayload);
        verify(jobMapper).insert(any(PrintingJob.class));
        verify(feieyunService).printWithCredential(anyString(), anyString(), anyString(), anyString(), eq(dispatchPayload), anyInt());

        // 2. 精确预览：与派发同一规则/设备/模板/渲染入口，内容逐字一致
        clearInvocations(jobMapper, feieyunService, templateEngine);
        List<PrintResolvedPreview> previews = dispatcher.previewExact(1, PrintScenario.ORDER, ctx, null, null);
        assertEquals(1, previews.size());
        PrintResolvedPreview p = previews.get(0);
        assertEquals(dispatchPayload, p.getContents().get(0), "精确预览内容必须与真实派发载荷逐字一致");
        assertEquals(rule.getId(), p.getRuleId());
        assertEquals(10L, p.getDeviceId());
        assertEquals("前台飞鹅打印机", p.getDeviceName());
        assertEquals("CLOUD", p.getTransport());
        assertEquals(101L, p.getTemplateId());
        assertEquals("tpl_sys_order", p.getTemplateCode());
        verify(templateEngine, times(1)).renderDynamicTicket(any(), any(), any());

        // 3. 只读：不插入打印任务、不更新任务、不调用云打印
        verify(jobMapper, never()).insert(any(PrintingJob.class));
        verify(jobMapper, never()).updateById(any(PrintingJob.class));
        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
    }

    @Test
    void exactPreviewHonorsOptionalRuleAndDeviceFilters() {
        PrintingRule r1 = rule(1L, 1, "order", 10L, 1);
        PrintingRule r2 = rule(2L, 1, "order", 20L, 1);
        when(ruleMapper.selectList(any())).thenReturn(Arrays.asList(r1, r2));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(deviceMapper.selectById(20L)).thenReturn(lanDevice(20L, 1));
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("ORDER"));
        stubOrderRender();

        PrintContext ctx = PrintContext.ofOrder(successOrder(100, 1), false);

        List<PrintResolvedPreview> byRule = dispatcher.previewExact(1, PrintScenario.ORDER, ctx, 2L, null);
        assertEquals(1, byRule.size());
        assertEquals(2L, byRule.get(0).getRuleId());
        assertEquals(20L, byRule.get(0).getDeviceId());

        List<PrintResolvedPreview> byDevice = dispatcher.previewExact(1, PrintScenario.ORDER, ctx, null, 10L);
        assertEquals(1, byDevice.size());
        assertEquals(1L, byDevice.get(0).getRuleId());
        assertEquals(10L, byDevice.get(0).getDeviceId());
    }

    @Test
    void exactPreviewWithoutEnabledRulesFailsLoudlyInsteadOfSilentSkip() {
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());
        // dispatch 在无规则时静默跳过，精确预览必须显式报错（拒绝样例兜底）
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> dispatcher.previewExact(1, PrintScenario.ORDER, PrintContext.ofOrder(successOrder(100, 1), false), null, null));
        assertTrue(ex.getMessage().contains("未配置生效打印规则"));
    }

    @Test
    void exactPreviewRejectsForeignOrMissingDeviceWithoutFallback() {
        PrintingRule rule = rule(1L, 1, "order", 10L, 1);
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule));
        // 设备属于其它门店：不允许跨店渲染，直接报错而不是静默跳过
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 2, "987654321"));
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class,
                () -> dispatcher.previewExact(1, PrintScenario.ORDER, PrintContext.ofOrder(successOrder(100, 1), false), null, null));
        assertTrue(ex.getMessage().contains("指定打印规则或设备不存在"));
    }

    @Test
    void exactPreviewWithoutConfiguredTemplateFailsLoudly() {
        PrintingRule rule = rule(1L, 1, "order", 10L, 1);
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(templateMapper.selectOne(any())).thenReturn(null); // 未配置模板
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> dispatcher.previewExact(1, PrintScenario.ORDER, PrintContext.ofOrder(successOrder(100, 1), false), null, null));
        assertTrue(ex.getMessage().contains("未配置小票打印模板"));
    }
}
