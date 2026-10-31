package com.lanf.printing.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
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
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.printing.service.impl.PrintDispatcherServiceImpl;
import com.lanf.service.IFeieyunService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PrintDispatcherServiceTest {

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

    @Test
    void testDispatchOrderCloudSuccess() throws Exception {
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(1L, 1, "order", 10L, 2)));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("ORDER"));
        when(templateEngine.parseDsl(anyString())).thenReturn(new PrintTemplateDsl());
        when(templateEngine.renderDynamicTicket(any(), any(), any())).thenReturn("<CB>结账单</CB>");
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("987654321"), anyString(), eq(2))).thenReturn("{\"ret\":0}");
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(501L);
            return 1;
        });

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);
        order.setTransac_status("success");

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.ORDER, PrintContext.ofOrder(order, false));

        assertEquals(1, results.size());
        PrintDispatchResult res = results.get(0);
        assertEquals(501L, res.getJobId());
        assertEquals("SENT", res.getStatus());
        assertEquals("CLOUD", res.getExecutor());
        assertEquals(PrintScenario.CHECKOUT, res.getScenario());
        assertEquals(2, res.getCopies());
        assertTrue(res.isSuccess());

        ArgumentCaptor<PrintingJob> jobCaptor = ArgumentCaptor.forClass(PrintingJob.class);
        verify(jobMapper).insert(jobCaptor.capture());
        assertEquals(PrintScenario.CHECKOUT, jobCaptor.getValue().getJob_type());

        verify(feieyunService).printWithCredential(anyString(), anyString(), anyString(), eq("987654321"), eq("<CB>结账单</CB>"), eq(2));
    }

    @Test
    void testDispatchKitchenLanPendingDevice() throws Exception {
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(2L, 1, "kitchen", 20L, 1)));
        when(deviceMapper.selectById(20L)).thenReturn(lanDevice(20L, 1));
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("KITCHEN"));
        when(templateEngine.parseDsl(anyString())).thenReturn(new PrintTemplateDsl());
        when(templateEngine.renderDynamicKitchenTickets(any(), any(), any(), any())).thenReturn(Collections.singletonList("<CB>后厨制作单</CB>"));
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(502L);
            return 1;
        });

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.KITCHEN, PrintContext.ofKitchen(order, null));

        assertEquals(1, results.size());
        PrintDispatchResult res = results.get(0);
        assertEquals(502L, res.getJobId());
        assertEquals("PENDING_DEVICE", res.getStatus());
        assertEquals("DEVICE", res.getExecutor());
        assertTrue(res.isSuccess());

        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
    }

    @Test
    void testDispatchWhenTemplateNotFoundInDb_FailsWithClearMessage() {
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(1L, 1, "order", 10L, 1)));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(templateMapper.selectOne(any())).thenReturn(null); // DB 中未配置模板

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.ORDER, PrintContext.ofOrder(order, false));

        assertEquals(1, results.size());
        PrintDispatchResult res = results.get(0);
        assertFalse(res.isSuccess());
        assertEquals("FAILED", res.getStatus());
        assertNotNull(res.getError());
        assertTrue(res.getError().contains("未配置小票打印模板"));
    }

    @Test
    void testReprintJobCloud() throws Exception {
        PrintingJob existing = new PrintingJob();
        existing.setId(601L);
        existing.setShop_id(1);
        existing.setDevice_id(10L);
        existing.setJob_type("order");
        existing.setPayload_text("小票内容");
        existing.setRetry_count(0);

        when(jobMapper.selectById(601L)).thenReturn(existing);
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("987654321"), eq("小票内容"), eq(1))).thenReturn("{\"ret\":0}");

        PrintDispatchResult res = dispatcher.reprintJob(601L, 9);
        assertNotNull(res);
        assertTrue(res.isSuccess());
        assertEquals("SENT", res.getStatus());

        ArgumentCaptor<PrintingJob> captor = ArgumentCaptor.forClass(PrintingJob.class);
        verify(jobMapper).updateById(captor.capture());
        assertEquals(1, captor.getValue().getRetry_count());
    }

    @Test
    void testDispatchOrderWithDeviceCredentials() throws Exception {
        PrintingDevice devWithCreds = new PrintingDevice();
        devWithCreds.setId(30L);
        devWithCreds.setShop_id(1);
        devWithCreds.setName("独立凭据飞鹅云机");
        devWithCreds.setTransport("CLOUD");
        devWithCreds.setBrand("飞鹅");
        devWithCreds.setConnection_json("{\"sn\":\"987654321\",\"user\":\"feie_user_1\",\"ukey\":\"feie_key_1\",\"apiUrl\":\"http://api.feieyun.cn/Api/Open/\"}");
        devWithCreds.setStatus("ONLINE");

        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(3L, 1, "order", 30L, 1)));
        when(deviceMapper.selectById(30L)).thenReturn(devWithCreds);
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("ORDER"));
        when(templateEngine.parseDsl(anyString())).thenReturn(new PrintTemplateDsl());
        when(templateEngine.renderDynamicTicket(any(), any(), any())).thenReturn("<CB>结账单</CB>");
        when(feieyunService.printWithCredential(eq("http://api.feieyun.cn/Api/Open/"), eq("feie_user_1"), eq("feie_key_1"), eq("987654321"), anyString(), eq(1)))
                .thenReturn("{\"ret\":0}");
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(503L);
            return 1;
        });

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.ORDER, PrintContext.ofOrder(order, false));

        assertEquals(1, results.size());
        PrintDispatchResult res = results.get(0);
        assertEquals(503L, res.getJobId());
        assertEquals("SENT", res.getStatus());
        assertTrue(res.isSuccess());

        verify(feieyunService).printWithCredential(eq("http://api.feieyun.cn/Api/Open/"), eq("feie_user_1"), eq("feie_key_1"), eq("987654321"), eq("<CB>结账单</CB>"), eq(1));
    }

    @Test
    void testDispatchWhenRuleExplicitlyDisabled_ReturnsEmptyAndDoesNotFallback() throws Exception {
        PrintingRule disabledRule = rule(4L, 1, "expedite", 10L, 1);
        disabledRule.setEnabled(0); // 用户主动禁用传菜票打印

        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(disabledRule));
        when(deviceMapper.selectList(any())).thenReturn(Collections.singletonList(cloudDevice(10L, 1, "987654321")));

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.EXPEDITE, PrintContext.ofOrder(order, false));

        assertTrue(results.isEmpty(), "当出票规则被主动禁用时，dispatch 必须返回空列表，严禁 fallback 兜底出票");
        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
        verify(jobMapper, never()).insert(any());
    }

    @Test
    void testDispatchWhenShopHasOtherRulesButNoRuleForScenario_ReturnsEmptyAndDoesNotFallback() throws Exception {
        // 针对 expedite 场景查无规则
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());
        // 门店已配置了其它出票规则（如 checkout/order 规则，总规则数 > 0）
        when(ruleMapper.selectCount(any())).thenReturn(2);
        // 门店内存在设备
        when(deviceMapper.selectList(any())).thenReturn(Collections.singletonList(cloudDevice(10L, 1, "987654321")));

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.EXPEDITE, PrintContext.ofOrder(order, false));

        assertTrue(results.isEmpty(), "门店已接入规则管理但未开启传菜场景时，dispatch 必须直接跳过，严禁 fallback 兜底出票");
        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
        verify(jobMapper, never()).insert(any());
    }

    @Test
    void testDispatchWhenShopHasZeroRules_FallsBackToDefaultDevice() throws Exception {
        // 场景无规则
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());
        // 门店全无任何出票规则（新店/冷启动空规则状态，总规则数 == 0）
        when(ruleMapper.selectCount(any())).thenReturn(0);
        when(deviceMapper.selectList(any())).thenReturn(Collections.singletonList(cloudDevice(10L, 1, "987654321")));
        when(deviceMapper.selectById(10L)).thenReturn(cloudDevice(10L, 1, "987654321"));
        when(templateMapper.selectOne(any())).thenReturn(createMockTemplate("CHECKOUT"));
        when(templateEngine.parseDsl(anyString())).thenReturn(new PrintTemplateDsl());
        when(templateEngine.renderDynamicTicket(any(), any(), any())).thenReturn("<CB>结账单</CB>");
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("987654321"), anyString(), eq(1)))
                .thenReturn("{\"ret\":0}");
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(504L);
            return 1;
        });

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);
        order.setTransac_status("success");

        List<PrintDispatchResult> results = dispatcher.dispatch(1, PrintScenario.CHECKOUT, PrintContext.ofOrder(order, false));

        assertEquals(1, results.size());
        assertTrue(results.get(0).isSuccess());
        assertEquals("SENT", results.get(0).getStatus());
        verify(feieyunService).printWithCredential(anyString(), anyString(), anyString(), eq("987654321"), eq("<CB>结账单</CB>"), eq(1));
    }

    @Test
    void packingWithoutRuleNeverFallsBackToDefaultDevice() {
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(ruleMapper.selectCount(any())).thenReturn(0);
        when(deviceMapper.selectList(any())).thenReturn(Collections.singletonList(cloudDevice(10L, 1, "987654321")));

        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);
        order.setDineInOrTakeOut("打包");

        List<PrintDispatchResult> results = dispatcher.dispatch(
                1, PrintScenario.PACKING, PrintContext.ofOrder(order, true));

        assertTrue(results.isEmpty(), "打包单必须显式配置 PACKING 规则后才允许出票");
        verify(deviceMapper, never()).selectList(any());
        verify(jobMapper, never()).insert(any());
    }
}
