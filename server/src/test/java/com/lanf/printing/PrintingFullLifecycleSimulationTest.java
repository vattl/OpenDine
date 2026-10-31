package com.lanf.printing;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.engine.PrintTemplateEngineImpl;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingJob;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.service.PrintingService;
import com.lanf.printing.service.impl.PrintDispatcherServiceImpl;
import com.lanf.service.IFeieyunService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/**
 * 打印模块全业务链路闭环模拟测试：
 * 1. 管理后台设备全生命周期（创建、自动注册飞鹅、多票据类型、平铺连接参数、状态探活、测试出票、清空队列、解绑删除）
 * 2. 打印规则配置与乐观锁版本控制
 * 3. 堂食/外卖订单支付成功自动触发前台结账单分发（CLOUD 飞鹅云打印）
 * 4. 自动接单/加菜多场景分发（KITCHEN 后厨单到 LAN 网口打印机，ORDER 加菜单到前台）
 * 5. KDS 划菜出票（SERVE 传菜单）
 * 6. 任务流水审计、重试补打（reprintJob）与队列清空
 */
public class PrintingFullLifecycleSimulationTest {

    private PrintingService printingService;
    private PrintDispatcherServiceImpl printDispatcherService;
    private PrintTemplateEngine templateEngine;

    private PrintingDeviceMapper deviceMapper;
    private PrintingRuleMapper ruleMapper;
    private PrintingJobMapper jobMapper;
    private IFeieyunService feieyunService;
    private IShopService shopService;

    private final Map<Long, PrintingDevice> dbDevices = new HashMap<>();
    private final Map<Long, PrintingRule> dbRules = new HashMap<>();
    private final Map<Long, PrintingJob> dbJobs = new HashMap<>();
    private long deviceIdSeq = 100L;
    private long ruleIdSeq = 200L;
    private long jobIdSeq = 500L;

    @BeforeEach
    void setup() {
        deviceMapper = mock(PrintingDeviceMapper.class);
        ruleMapper = mock(PrintingRuleMapper.class);
        jobMapper = mock(PrintingJobMapper.class);
        feieyunService = mock(IFeieyunService.class);
        shopService = mock(IShopService.class);

        templateEngine = new PrintTemplateEngineImpl();
        com.lanf.printing.mapper.PrintingTemplateMapper templateMapper = mock(com.lanf.printing.mapper.PrintingTemplateMapper.class);
        ObjectMapper objectMapper = new ObjectMapper();

        printingService = new PrintingService();
        ReflectionTestUtils.setField(printingService, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(printingService, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(printingService, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(printingService, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(printingService, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(printingService, "shopService", shopService);
        ReflectionTestUtils.setField(printingService, "objectMapper", objectMapper);

        printDispatcherService = new PrintDispatcherServiceImpl();
        ReflectionTestUtils.setField(printDispatcherService, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(printDispatcherService, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(printDispatcherService, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(printDispatcherService, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(printDispatcherService, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(printDispatcherService, "templateEngine", templateEngine);

        when(templateMapper.selectOne(any())).thenAnswer(inv -> {
            com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?> qw = inv.getArgument(0);
            String targetScenario = "ORDER";
            if (qw != null) {
                qw.getSqlSegment(); // 触发 MyBatis-Plus 构建 paramNameValuePairs
                Map<String, Object> params = qw.getParamNameValuePairs();
                if (params != null) {
                    for (Object v : params.values()) {
                        if (v instanceof String) {
                            String s = ((String) v).toUpperCase();
                            if (s.contains("KITCHEN")) targetScenario = "KITCHEN";
                            else if (s.contains("EXPEDITE") || s.contains("SERVE")) targetScenario = "EXPEDITE";
                            else if (s.contains("SHIFT")) targetScenario = "SHIFT";
                            else if (s.contains("REFUND")) targetScenario = "REFUND";
                            else if (s.contains("LABEL")) targetScenario = "LABEL";
                            else if (s.contains("TEST")) targetScenario = "TEST";
                        }
                    }
                }
            }
            com.lanf.printing.entity.PrintingTemplate pt = new com.lanf.printing.entity.PrintingTemplate();
            pt.setId(999L);
            pt.setShop_id(0);
            pt.setTemplate_code("tpl_sys_" + targetScenario.toLowerCase());
            pt.setTemplate_name("系统默认模板");
            pt.setScenario(targetScenario);
            pt.setIs_default(1);
            try {
                pt.setTemplate_json(objectMapper.writeValueAsString(templateEngine.buildDefaultDsl(targetScenario, "58mm")));
            } catch (Exception e) {
                pt.setTemplate_json("{}");
            }
            return pt;
        });

        // 模拟 DB 交互
        when(deviceMapper.insert(any(PrintingDevice.class))).thenAnswer(inv -> {
            PrintingDevice d = inv.getArgument(0);
            if (d.getId() == null) {
                d.setId(++deviceIdSeq);
            }
            dbDevices.put(d.getId(), d);
            return 1;
        });
        when(deviceMapper.selectById(anyLong())).thenAnswer(inv -> dbDevices.get(inv.getArgument(0)));
        when(deviceMapper.selectOne(any())).thenAnswer(inv -> {
            return dbDevices.values().stream().findFirst().orElse(null);
        });
        when(deviceMapper.deleteById(anyLong())).thenAnswer(inv -> {
            dbDevices.remove((Long) inv.getArgument(0));
            return 1;
        });

        when(ruleMapper.insert(any(PrintingRule.class))).thenAnswer(inv -> {
            PrintingRule r = inv.getArgument(0);
            if (r.getId() == null) {
                r.setId(++ruleIdSeq);
            }
            dbRules.put(r.getId(), r);
            return 1;
        });
        when(ruleMapper.delete(any())).thenAnswer(inv -> {
            dbRules.clear();
            return 1;
        });
        when(ruleMapper.selectList(any())).thenAnswer(inv -> {
            QueryWrapper<PrintingRule> qw = inv.getArgument(0);
            if (qw != null) {
                qw.getSqlSegment(); // 触发 MyBatis-Plus 构建 paramNameValuePairs
                Map<String, Object> params = qw.getParamNameValuePairs();
                if (params != null) {
                    for (String sc : Arrays.asList("checkout", "pre_checkout", "full_order", "kitchen", "expedite", "takeout", "shift", "refund", "label", "test", "order", "serve")) {
                        if (params.containsValue(sc)) {
                            List<PrintingRule> matched = new ArrayList<>();
                            for (PrintingRule r : dbRules.values()) {
                                if (sc.equalsIgnoreCase(r.getScenario())) {
                                    matched.add(r);
                                }
                            }
                            return matched;
                        }
                    }
                }
            }
            return new ArrayList<>(dbRules.values());
        });

        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            if (j.getId() == null) {
                j.setId(++jobIdSeq);
            }
            dbJobs.put(j.getId(), j);
            return 1;
        });
        when(jobMapper.selectById(anyLong())).thenAnswer(inv -> dbJobs.get(inv.getArgument(0)));
        when(jobMapper.updateById(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            dbJobs.put(j.getId(), j);
            return 1;
        });

        Shop mockShop = new Shop();
        mockShop.setId(1);
        mockShop.setName("美味烧烤总店");
        when(shopService.getById(1)).thenReturn(mockShop);
    }

    @Test
    @DisplayName("完整业务链路闭环模拟：设备注册 -> 规则绑定 -> 支付前台出票 -> 接单后厨出票 -> 传菜出票 -> 补打与清空队列")
    void simulateFullPrintingLifecycle() throws Exception {
        int shopId = 1;
        int adminId = 9;

        // ==========================================
        // 环节 1: 管理员配置云打印机与网口打印机
        // ==========================================
        // 1.1 创建前台飞鹅云打印机
        Map<String, Object> cloudDevBody = new LinkedHashMap<>();
        cloudDevBody.put("name", "前台飞鹅云打印机");
        cloudDevBody.put("transport", "CLOUD");
        cloudDevBody.put("vendor", "飞鹅云");
        cloudDevBody.put("sn", "924698188");
        cloudDevBody.put("key", "secretKey999");
        cloudDevBody.put("user", "shop_admin@feie.com");
        cloudDevBody.put("ukey", "REDACTED_ROTATE_CREDENTIAL");
        cloudDevBody.put("url", "http://api.feieyun.cn/Api/Open/");
        cloudDevBody.put("paperSize", "58mm");
        cloudDevBody.put("ticketTypes", Arrays.asList("FULL_ORDER", "PRE_CHECKOUT", "CHECKOUT", "SERVE"));

        when(feieyunService.addPrinterWithCredential(anyString(), anyString(), anyString(), anyString()))
                .thenReturn("{\"ret\":0,\"msg\":\"ok\"}");

        Map<String, Object> createdCloud = printingService.createDevice(shopId, cloudDevBody, adminId);
        assertNotNull(createdCloud);
        Long cloudDevId = (Long) createdCloud.get("id");
        assertEquals("924698188", createdCloud.get("sn"));
        assertEquals("CLOUD", createdCloud.get("transport"));
        // 验证自动调用飞鹅开放平台绑定打印机（带独立凭据）
        verify(feieyunService).addPrinterWithCredential(
                eq("http://api.feieyun.cn/Api/Open/"),
                eq("shop_admin@feie.com"),
                eq("REDACTED_ROTATE_CREDENTIAL"),
                eq("924698188#secretKey999#前台飞鹅云打印机"));

        // 1.2 创建后厨局域网 LAN 打印机
        Map<String, Object> lanDevBody = new LinkedHashMap<>();
        lanDevBody.put("name", "后厨网口打印机");
        lanDevBody.put("transport", "LAN");
        lanDevBody.put("vendor", "爱普生");
        lanDevBody.put("ip", "192.168.1.200");
        lanDevBody.put("port", 9100);
        lanDevBody.put("paperSize", "80mm");
        lanDevBody.put("ticketTypes", Arrays.asList("KITCHEN", "EXPEDITE"));

        Map<String, Object> createdLan = printingService.createDevice(shopId, lanDevBody, adminId);
        Long lanDevId = (Long) createdLan.get("id");
        assertEquals("LAN", createdLan.get("transport"));
        assertEquals("192.168.1.200", createdLan.get("ip"));

        // 1.3 探活飞鹅云打印机在线状态
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("924698188")))
                .thenReturn("在线，工作状态正常");
        Map<String, Object> probeRes = printingService.probeDeviceStatus(shopId, cloudDevId);
        assertEquals(true, probeRes.get("online"));
        assertEquals("ONLINE", probeRes.get("status"));
        assertEquals("NORMAL", probeRes.get("paperStatus"));

        // ==========================================
        // 环节 2: 配置出票规则 (场景 -> 设备)
        // ==========================================
        Map<String, Object> ruleConfigBody = new LinkedHashMap<>();
        ruleConfigBody.put("version", 0);
        List<Map<String, Object>> rulesList = new ArrayList<>();

        // 前台小票 -> 飞鹅云打印机
        Map<String, Object> rOrder = new LinkedHashMap<>();
        rOrder.put("scenario", "order");
        rOrder.put("deviceId", cloudDevId);
        rOrder.put("copies", 1);
        rOrder.put("enabled", true);
        rulesList.add(rOrder);

        // 后厨制作单 -> 后厨网口打印机
        Map<String, Object> rKitchen = new LinkedHashMap<>();
        rKitchen.put("scenario", "kitchen");
        rKitchen.put("deviceId", lanDevId);
        rKitchen.put("copies", 1);
        rKitchen.put("enabled", true);
        rulesList.add(rKitchen);

        // 传菜单 -> 飞鹅云打印机
        Map<String, Object> rServe = new LinkedHashMap<>();
        rServe.put("scenario", "serve");
        rServe.put("deviceId", cloudDevId);
        rServe.put("copies", 1);
        rServe.put("enabled", true);
        rulesList.add(rServe);

        ruleConfigBody.put("rules", rulesList);
        Map<String, Object> savedRules = printingService.saveRules(shopId, ruleConfigBody, adminId);
        assertEquals(1, savedRules.get("version"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> savedItems = (List<Map<String, Object>>) savedRules.get("rules");
        assertEquals(3, savedItems.size());

        // ==========================================
        // 环节 3: 业务链路 1 —— 顾客支付成功，自动打印前台结账单 (ORDER 场景)
        // ==========================================
        Order paidOrder = createMockOrder(shopId, "ORD-20260830-001", "A08", "堂食");
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("924698188"), anyString(), eq(1)))
                .thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"feie_order_001\"}");

        // PrintDispatcherService.dispatch(ORDER)
        List<PrintDispatchResult> orderDispatchResults = printDispatcherService.dispatch(
                shopId, PrintScenario.ORDER, PrintContext.ofOrder(paidOrder, false));

        assertEquals(1, orderDispatchResults.size());
        PrintDispatchResult orderRes = orderDispatchResults.get(0);
        assertTrue(orderRes.isSuccess());
        assertEquals("SENT", orderRes.getStatus());
        assertEquals("CLOUD", orderRes.getExecutor());
        assertEquals(PrintScenario.CHECKOUT, orderRes.getScenario());
        assertEquals(cloudDevId, orderRes.getDeviceId());
        assertTrue(orderRes.getPayloadText().contains("结账单"));
        assertTrue(orderRes.getPayloadText().contains("炭烤羊肉")); // 菜品名统一 4 字以内

        // 验证使用独立设备凭据调用了飞鹅平台
        verify(feieyunService).printWithCredential(
                anyString(), eq("shop_admin@feie.com"), eq("REDACTED_ROTATE_CREDENTIAL"), eq("924698188"), anyString(), eq(1));

        // ==========================================
        // 环节 4: 业务链路 2 —— 门店自动接单，后厨制作单分发 (KITCHEN 场景 -> LAN 设备)
        // ==========================================
        List<PrintDispatchResult> kitchenDispatchResults = printDispatcherService.dispatch(
                shopId, PrintScenario.KITCHEN, PrintContext.ofKitchen(paidOrder, null));

        assertEquals(1, kitchenDispatchResults.size());
        PrintDispatchResult kitchenRes = kitchenDispatchResults.get(0);
        assertTrue(kitchenRes.isSuccess());
        assertEquals("PENDING_DEVICE", kitchenRes.getStatus());
        assertEquals("DEVICE", kitchenRes.getExecutor()); // 端侧网口打印机执行
        assertEquals(lanDevId, kitchenRes.getDeviceId());
        assertTrue(kitchenRes.getPayloadText().contains("厨房小票"));

        // ==========================================
        // 环节 5: 业务链路 3 —— KDS 划菜，自动打印传菜单 (SERVE 场景)
        // ==========================================
        OrderDetail detail = paidOrder.getGoods_list().get(0);
        List<PrintDispatchResult> serveDispatchResults = printDispatcherService.dispatch(
                shopId, PrintScenario.SERVE, PrintContext.ofServe(paidOrder, detail, 5));

        assertEquals(1, serveDispatchResults.size());
        PrintDispatchResult serveRes = serveDispatchResults.get(0);
        assertTrue(serveRes.isSuccess());
        assertEquals("SENT", serveRes.getStatus());
        assertEquals(cloudDevId, serveRes.getDeviceId());
        assertEquals(PrintScenario.EXPEDITE, serveRes.getScenario());
        assertTrue(serveRes.getPayloadText().contains("传菜单"));

        // ==========================================
        // 环节 6: 运维/后台操作 —— 补打流水 (reprintJob) 与清空排队队列 (clear-queue)
        // ==========================================
        // 6.1 补打前台结账单
        PrintDispatchResult reprintRes = printDispatcherService.reprintJob(orderRes.getJobId(), adminId);
        assertTrue(reprintRes.isSuccess());
        assertEquals("SENT", reprintRes.getStatus());
        PrintingJob updatedJob = dbJobs.get(orderRes.getJobId());
        assertEquals(1, updatedJob.getRetry_count());

        // 6.2 清空云打印机队列
        when(feieyunService.clearPrintQueueWithCredential(anyString(), anyString(), anyString(), eq("924698188")))
                .thenReturn("{\"ret\":0,\"msg\":\"ok\"}");
        Map<String, Object> clearRes = printingService.clearDeviceQueue(shopId, cloudDevId, adminId);
        assertTrue((Boolean) clearRes.get("success"));
        assertEquals("924698188", clearRes.get("sn"));
        verify(feieyunService).clearPrintQueueWithCredential(
                eq("http://api.feieyun.cn/Api/Open/"),
                eq("shop_admin@feie.com"),
                eq("REDACTED_ROTATE_CREDENTIAL"),
                eq("924698188"));

        // 6.3 尝试删除正被规则引用的打印机 -> 预期被拦截
        ApiException delEx = assertThrows(ApiException.class, () -> printingService.deleteDevice(shopId, cloudDevId));
        assertEquals("PRINT_DEVICE_IN_USE_BY_RULE", delEx.getErrorCode());

        // 6.4 清除规则后删除云打印机 -> 自动从飞鹅云平台解绑
        dbRules.clear();
        when(feieyunService.deletePrinterWithCredential(anyString(), anyString(), anyString(), eq("924698188")))
                .thenReturn("{\"ret\":0,\"msg\":\"ok\"}");
        printingService.deleteDevice(shopId, cloudDevId);
        assertNull(dbDevices.get(cloudDevId));
        verify(feieyunService).deletePrinterWithCredential(
                eq("http://api.feieyun.cn/Api/Open/"),
                eq("shop_admin@feie.com"),
                eq("REDACTED_ROTATE_CREDENTIAL"),
                eq("924698188"));
    }

    private Order createMockOrder(int shopId, String orderNo, String tableNo, String diningType) {
        Order o = new Order();
        o.setId(1001);
        o.setShop_id(shopId);
        o.setOrder_no(orderNo);
        o.setTable_number(tableNo);
        o.setDineInOrTakeOut(diningType);
        o.setNumber_of_diners("4");
        o.setSett_amount(128.0);
        o.setTransac_status("success");
        o.setOrder_time(new Date());

        List<OrderDetail> details = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(5001);
        d1.setMId(1001);
        d1.setName("炭烤羊肉串");
        d1.setQuantity("10");
        d1.setTotal_price(50.0);
        d1.setLine_status("normal");
        details.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(5002);
        d2.setMId(1001);
        d2.setName("招牌烤生蚝");
        d2.setQuantity("6");
        d2.setTotal_price(48.0);
        d2.setLine_status("normal");
        details.add(d2);

        o.setGoods_list(details);
        return o;
    }
}
