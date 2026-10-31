package com.lanf.printing.engine;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PrintTemplateEngineTest {

    private PrintTemplateEngineImpl engine;

    @BeforeEach
    void setUp() {
        engine = new PrintTemplateEngineImpl();
    }

    private Order createTestOrder() {
        Order order = new Order();
        order.setId(1001);
        order.setOrder_no("ORD-20260830-001");
        order.setShop_id(1);
        order.setTable_number("A08");
        order.setDineInOrTakeOut("堂食");
        order.setOrder_time(new Date());
        order.setPay_time(new Date());
        order.setTransac_status("success");
        order.setSett_amount(38.0);
        order.setService_fee(0.0);
        order.setDiscount_amount(5.0);
        order.setPayment_method("微信支付");
        order.setRemark("少油少盐");

        List<OrderDetail> items = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(1);
        d1.setName("特色油边");
        d1.setCid("1");
        d1.setQuantity("2");
        d1.setTotal_price(20.0);
        d1.setSelectedSpicy("{\"name\":\"微辣\"}");
        items.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(2);
        d2.setName("秘制羊肉串");
        d2.setCid("2");
        d2.setQuantity("1");
        d2.setTotal_price(18.0);
        d2.setSelectedSpicy("{\"name\":\"中辣\"}");
        items.add(d2);

        order.setGoods_list(items);
        return order;
    }

    @Test
    void testRenderReceiptTicket() {
        Order order = createTestOrder();
        String ticket = engine.renderReceiptTicket(order, false, PrintTemplateOptions.defaultOptions());

        assertNotNull(ticket);
        assertTrue(ticket.contains("老肥油边王"));
        assertTrue(ticket.contains("A08"));
        assertTrue(ticket.contains("结账单"));
        assertTrue(ticket.contains("特色油边"));
        assertTrue(ticket.contains("秘制羊肉")); // 菜品名统一 4 字以内
        assertTrue(ticket.contains("实付合计：38.00元"));
        assertTrue(ticket.contains("少油少盐"));
    }

    @Test
    void testRenderKitchenTickets() {
        Order order = createTestOrder();
        List<String> tickets = engine.renderKitchenTickets(order, Collections.singleton("1"), PrintTemplateOptions.defaultOptions());

        assertNotNull(tickets);
        assertFalse(tickets.isEmpty());
        assertTrue(tickets.get(0).contains("厨房小票"));
        assertTrue(tickets.get(0).contains("A08"));
    }

    @Test
    void packingDefaultDslIsASeparateNonPaymentTicket() {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("PACKING", "58mm");

        assertEquals("PACKING", dsl.getScenario());
        assertTrue(dsl.getBlocks().stream().anyMatch(block ->
                "HEADER".equals(block.getType())
                        && "打包单".equals(block.getConfig().get("customTitle"))));
        assertTrue(dsl.getBlocks().stream().anyMatch(block -> "DISH_ITEMS".equals(block.getType())));
        assertFalse(dsl.getBlocks().stream().anyMatch(block -> "PAYMENT_SUMMARY".equals(block.getType())));
    }

    @Test
    void testRenderServeTicket() {
        Order order = createTestOrder();
        OrderDetail detail = order.getGoods_list().get(0);
        String ticket = engine.renderServeTicket(order, detail, 2, PrintTemplateOptions.defaultOptions());

        assertNotNull(ticket);
        assertTrue(ticket.contains("传菜单"));
        assertTrue(ticket.contains("特色油边"));
        assertTrue(ticket.contains("2"));
        assertTrue(ticket.contains("A08"));
    }

    @Test
    void testRenderShiftTicket() {
        Shift shift = new Shift();
        shift.setId(10L);
        shift.setShop_id(1);
        shift.setAdmin_id(5);
        shift.setStart_cash(BigDecimal.valueOf(500));
        shift.setOrder_count(42);
        shift.setTotal_amount(BigDecimal.valueOf(3280.50));
        shift.setStart_time(new Date());
        shift.setEnd_time(new Date());

        Map<String, Object> stats = new LinkedHashMap<>();
        stats.put("微信支付", "¥2000.00");
        stats.put("支付宝", "¥1280.50");

        String ticket = engine.renderShiftTicket(shift, stats, PrintTemplateOptions.defaultOptions());
        assertNotNull(ticket);
        assertTrue(ticket.contains("收银交接班报表"));
        assertTrue(ticket.contains("3280.50"));
        assertTrue(ticket.contains("¥2000.00"));
    }

    @Test
    void testRenderRefundTicket() {
        Order order = createTestOrder();
        Map<String, Object> refund = new LinkedHashMap<>();
        refund.put("refundAmount", "33.00");
        refund.put("reason", "顾客要求退单");
        refund.put("operator", "张店长");

        String ticket = engine.renderRefundTicket(order, refund, PrintTemplateOptions.defaultOptions());
        assertNotNull(ticket);
        assertTrue(ticket.contains("退款单据"));
        assertTrue(ticket.contains("33.00"));
        assertTrue(ticket.contains("顾客要求退单"));
    }

    @Test
    void testRenderTestTicket() {
        String ticket = engine.renderTestTicket("cutter_test", "前台小票机", "CLOUD", "飞鹅", 1);
        assertNotNull(ticket);
        assertTrue(ticket.contains("打印测试单"));
        assertTrue(ticket.contains("切刀自检测试"));
    }

    @Test
    void testSpicyJsonParsing() {
        // {"辣度":"不辣"}
        org.junit.jupiter.api.Assertions.assertEquals("不辣", PrintTemplateEngineImpl.getSpicyText("{\"辣度\":\"不辣\"}"));
        org.junit.jupiter.api.Assertions.assertEquals("(不辣)", PrintTemplateEngineImpl.formatPrintSpecInParens("{\"辣度\":\"不辣\"}"));

        // {"辣度":"微辣"}
        org.junit.jupiter.api.Assertions.assertEquals("微辣", PrintTemplateEngineImpl.getSpicyText("{\"辣度\":\"微辣\"}"));
        org.junit.jupiter.api.Assertions.assertEquals("(微辣)", PrintTemplateEngineImpl.formatPrintSpecInParens("{\"辣度\":\"微辣\"}"));

        // {"口味":"特辣"}
        org.junit.jupiter.api.Assertions.assertEquals("特辣", PrintTemplateEngineImpl.getSpicyText("{\"口味\":\"特辣\"}"));
        org.junit.jupiter.api.Assertions.assertEquals("(特辣)", PrintTemplateEngineImpl.formatPrintSpecInParens("{\"口味\":\"特辣\"}"));

        // {"name":"中辣"}
        org.junit.jupiter.api.Assertions.assertEquals("中辣", PrintTemplateEngineImpl.getSpicyText("{\"name\":\"中辣\"}"));
        org.junit.jupiter.api.Assertions.assertEquals("(中辣)", PrintTemplateEngineImpl.formatPrintSpecInParens("{\"name\":\"中辣\"}"));

        // {"辣度":["微辣","少盐"]}
        org.junit.jupiter.api.Assertions.assertEquals("微辣,少盐", PrintTemplateEngineImpl.getSpicyText("{\"辣度\":[\"微辣\",\"少盐\"]}"));

        // 纯文本 "(微辣)" 或 "微辣"
        org.junit.jupiter.api.Assertions.assertEquals("微辣", PrintTemplateEngineImpl.getSpicyText("微辣"));
        org.junit.jupiter.api.Assertions.assertEquals("(微辣)", PrintTemplateEngineImpl.formatPrintSpecInParens("(微辣)"));

        // null 或空字符串
        org.junit.jupiter.api.Assertions.assertNull(PrintTemplateEngineImpl.getSpicyText(null));
        org.junit.jupiter.api.Assertions.assertNull(PrintTemplateEngineImpl.getSpicyText(""));
        org.junit.jupiter.api.Assertions.assertEquals("", PrintTemplateEngineImpl.formatPrintSpecInParens(null));
    }

    @Test
    void testReceiptWithSpicyJson() {
        Order order = new Order();
        order.setId(1002);
        order.setOrder_no("ORD-20260831-002");
        order.setShop_id(1);
        order.setTransac_status("success");
        order.setSett_amount(15.0);

        List<OrderDetail> items = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(10);
        d1.setName("油边王");
        d1.setQuantity("1");
        d1.setTotal_price(15.0);
        d1.setSelectedSpicy("{\"辣度\":\"不辣\"}");
        items.add(d1);
        order.setGoods_list(items);

        String ticket = engine.renderReceiptTicket(order, false, PrintTemplateOptions.defaultOptions());
        assertNotNull(ticket);
        // 应该包含 "油边王(不辣)"
        // 需求：菜名统一 4 字以内、去掉名称后的括号规格内容
        assertTrue(ticket.contains("油边王"));
        assertFalse(ticket.contains("(不辣)"));
        // 绝不应该包含原生 JSON 字符串
        assertFalse(ticket.contains("{\"辣度\""));
    }

    @Test
    void testBuildDefaultDslAndRenderDynamic() {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        assertNotNull(dsl);
        assertNotNull(dsl.getBlocks());
        org.junit.jupiter.api.Assertions.assertTrue(dsl.getBlocks().size() >= 5);

        Order order = createTestOrder();
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertNotNull(ticket);
        assertTrue(ticket.contains("老肥油边王"));
        assertTrue(ticket.contains("A08"));
        assertTrue(ticket.contains("38.00元"));
        assertTrue(ticket.contains("<CUT>"));
    }

    @Test
    void testDynamicKitchenTicketsWithCidFilter() {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("KITCHEN", "58mm");
        Order order = createTestOrder();
        java.util.Set<String> filter = new java.util.HashSet<>(java.util.Collections.singletonList("1"));

        List<String> tickets = engine.renderDynamicKitchenTickets(order, dsl, filter, PrintTemplateOptions.defaultOptions());
        assertNotNull(tickets);
        org.junit.jupiter.api.Assertions.assertEquals(1, tickets.size());
        assertTrue(tickets.get(0).contains("特色油边"));
    }

    @Test
    void testCustomDslWithDisabledBlocks() {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        // Disable Footer & Remark
        for (com.lanf.printing.model.PrintTemplateDsl.TemplateBlock b : dsl.getBlocks()) {
            if ("FOOTER".equals(b.getType()) || "REMARK".equals(b.getType())) {
                b.setEnabled(false);
            }
        }
        Order order = createTestOrder();
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertNotNull(ticket);
        assertFalse(ticket.contains("-----------感谢惠顾-----------"));
        assertFalse(ticket.contains("少油少盐"));
    }
    // ===== 回归：金额口径与 demo 对齐（合计=明细汇总，附加费独立成行，不伪造时间） =====
    @Test
    void testDynamicReceipt_extraFeeLineConsistentWithGoodsTotal() {
        Order order = createTestOrder(); // 明细 20+18=38；实付 38 = 明细38 + 附加5 - 优惠5
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("原价合计：38.00元"));
        assertTrue(ticket.contains("附加费用(打包/配送/服务)：5.00元"));
        assertTrue(ticket.contains("实付合计：38.00元"));
    }

    @Test
    void testDynamicReceipt_pureDiscount_noExtraFeeLine() {
        Order order = createTestOrder();
        order.setSett_amount(33.0); // 纯优惠 5，无附加费
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("原价合计：38.00元"));
        assertTrue(ticket.contains("优惠减免：-5.00元"));
        assertFalse(ticket.contains("附加费用"));
        assertTrue(ticket.contains("实付合计：33.00元"));
    }

    @Test
    void testDynamicReceipt_noFakeOrderTimeWhenNull() {
        Order order = createTestOrder();
        order.setOrder_time(null);
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertFalse(ticket.contains("下单时间"));
    }

    // ===== 回归：退款桌号只在真实外送订单时回退"外卖" =====
    @Test
    void testDynamicRefund_takeoutTableFallbackOnlyForRealTakeout() {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("REFUND", "58mm");
        Map<String, Object> refund = new LinkedHashMap<>();
        refund.put("refundAmount", "33.00");
        refund.put("reason", "顾客要求退单");
        refund.put("operator", "张店长");

        Order takeout = createTestOrder();
        takeout.setTable_number(null);
        takeout.setDineInOrTakeOut("外卖");
        String t1 = engine.renderDynamicRefundTicket(takeout, dsl, refund, PrintTemplateOptions.defaultOptions());
        assertTrue(t1.contains("桌号: 外卖"));

        Order dine = createTestOrder();
        dine.setTable_number(null);
        dine.setDineInOrTakeOut("堂食");
        String t2 = engine.renderDynamicRefundTicket(dine, dsl, refund, PrintTemplateOptions.defaultOptions());
        assertFalse(t2.contains("外卖"));
        assertTrue(t2.contains("桌号: "));
    }
    // ===== 回归：分割线按纸宽生成（58mm=16 全角列/32 个 '-', 80mm=24 全角列/48 个 '-'） =====
    @Test
    void testDynamicReceipt_dividerWidthByPaperSize() {
        com.lanf.printing.model.PrintTemplateDsl dsl58 = engine.buildDefaultDsl("ORDER", "58mm");
        com.lanf.printing.model.PrintTemplateDsl dsl80 = engine.buildDefaultDsl("ORDER", "80mm");
        String t58 = engine.renderDynamicTicket(createTestOrder(), dsl58, PrintTemplateOptions.defaultOptions());
        String t80 = engine.renderDynamicTicket(createTestOrder(), dsl80, PrintTemplateOptions.defaultOptions());
        assertTrue(t58.contains(dashes(32)));
        assertFalse(t58.contains(dashes(48)));
        assertTrue(t80.contains(dashes(48)));
    }

    @Test
    void testDynamicRefund_dividerWidthByPaperSize() {
        Map<String, Object> refund = new LinkedHashMap<>();
        refund.put("refundAmount", "33.00");
        com.lanf.printing.model.PrintTemplateDsl dsl58 = engine.buildDefaultDsl("REFUND", "58mm");
        String r58 = engine.renderDynamicRefundTicket(createTestOrder(), dsl58, refund, PrintTemplateOptions.defaultOptions());
        assertTrue(r58.contains(dashes(32)));
        assertFalse(r58.contains(dashes(48)));
    }

    @Test
    void testDynamicTestTicket_dividerWidthByPaperSize() {
        com.lanf.printing.model.PrintTemplateDsl dsl58 = engine.buildDefaultDsl("TEST", "58mm");
        String t58 = engine.renderDynamicTestTicket(dsl58, "STANDARD_RECEIPT", "前台小票机", "CLOUD", "飞鹅", 1);
        assertTrue(t58.contains(dashes(32)));
        assertFalse(t58.contains(dashes(48)));
    }

    private String dashes(int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            sb.append('-');
        }
        return sb.toString();
    }
    // ===== 回归：各场景读取 JSON 中的 rawTemplate 解析组装（TEXT 模式，参考飞鹅 demo 变量占位） =====
    @Test
    void testRawTemplate_shiftScenario() {
        Shift shift = new Shift();
        shift.setId(10L);
        shift.setShop_id(1);
        shift.setAdmin_id(5);
        shift.setStart_cash(BigDecimal.valueOf(500));
        shift.setOrder_count(42);
        shift.setTotal_amount(BigDecimal.valueOf(3280.50));
        shift.setStart_time(new Date());
        shift.setEnd_time(new Date());
        Map<String, Object> stats = new LinkedHashMap<>();
        stats.put("微信支付", "¥2000.00");

        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("SHIFT", "58mm");
        dsl.setMode("TEXT");
        dsl.setRawTemplate("<CB>{门店ID}交接班报表</CB>\n班次: {shiftId}\n总单数: {orderCount}\n实收总额: {totalAmount}\n{微信支付}\n{printTime}");
        dsl.setBlocks(new ArrayList<>());
        String ticket = engine.renderDynamicShiftTicket(shift, dsl, stats, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("交接班报表"));
        assertTrue(ticket.contains("班次: 10"));
        assertTrue(ticket.contains("总单数: 42"));
        assertTrue(ticket.contains("实收总额: 3280.50"));
        assertTrue(ticket.contains("¥2000.00"));
        assertFalse(ticket.contains("{shiftId}"));
    }

    @Test
    void testRawTemplate_refundScenario() {
        Order order = createTestOrder();
        Map<String, Object> refund = new LinkedHashMap<>();
        refund.put("refundAmount", "33.00");
        refund.put("reason", "顾客要求退单");
        refund.put("operator", "张店长");
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("REFUND", "58mm");
        dsl.setMode("TEXT");
        dsl.setRawTemplate("<CB>退款单据</CB>\n原订单号: {orderNo}\n桌号: {桌号}\n<B>退款金额: ¥{refundAmount}</B>\n原因: {reason}\n操作员: {operator}");
        dsl.setBlocks(new ArrayList<>());
        String ticket = engine.renderDynamicRefundTicket(order, dsl, refund, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("退款单据"));
        assertTrue(ticket.contains("原订单号: ORD-20260830-001"));
        assertTrue(ticket.contains("桌号: A08"));
        assertTrue(ticket.contains("退款金额: ¥33.00"));
        assertTrue(ticket.contains("原因: 顾客要求退单"));
        assertTrue(ticket.contains("操作员: 张店长"));
    }

    @Test
    void testRawTemplate_labelScenario() {
        Order order = createTestOrder();
        OrderDetail detail = order.getGoods_list().get(0);
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("LABEL", "58mm");
        dsl.setMode("TEXT");
        dsl.setRawTemplate("{品名}\n规格: {规格}\n数量: {数量}\n单价: {单价}");
        dsl.setBlocks(new ArrayList<>());
        String ticket = engine.renderDynamicLabelTicket(order, detail, dsl, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("特色油边"));
        assertTrue(ticket.contains("数量: 2"));
    }

    @Test
    void testRawTemplate_kitchenScenario() {
        Order order = createTestOrder();
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("KITCHEN", "58mm");
        dsl.setMode("TEXT");
        dsl.setRawTemplate("<CB>后厨单</CB>\n桌号: {桌号}\n{菜品} x{数量}");
        dsl.setBlocks(new ArrayList<>());
        List<String> tickets = engine.renderDynamicKitchenTickets(order, dsl, Collections.singleton("1"), PrintTemplateOptions.defaultOptions());
        assertNotNull(tickets);
        assertEquals(1, tickets.size());
        assertTrue(tickets.get(0).contains("后厨单"));
        assertTrue(tickets.get(0).contains("特色油边"));
    }
    // ===== 回归：{if:} 条件块解析（堂食→台号 / 打包→取餐码，取餐码=订单自增ID） =====
    private String renderOrderRaw(String template, Order order) {
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        dsl.setMode("TEXT");
        dsl.setRawTemplate(template);
        dsl.setBlocks(new ArrayList<>());
        return engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
    }

    @Test
    void testIfBlock_dineInShowsTableNo() {
        Order order = createTestOrder(); // 堂食, 桌号 A08, id=1001
        String ticket = renderOrderRaw(
                "<CB>点餐单</CB>\n{if:用餐方式=堂食}台号: {桌号}{else}取餐码: {取餐码}{/if}\n{菜品} x{数量}",
                order);
        assertTrue(ticket.contains("台号: A08"));
        assertFalse(ticket.contains("取餐码"));
        assertTrue(ticket.contains("特色油边"));
    }

    @Test
    void testIfBlock_takeoutShowsPickupCode() {
        Order order = createTestOrder();
        order.setDineInOrTakeOut("打包");
        order.setTable_number(""); // 打包无台号，取餐码=订单ID
        String ticket = renderOrderRaw(
                "<CB>外卖单</CB>\n{if:用餐方式=堂食}台号: {桌号}{else}取餐码: {取餐码}{/if}",
                order);
        assertTrue(ticket.contains("取餐码: 1001"));
        assertFalse(ticket.contains("台号"));
    }

    @Test
    void testIfBlock_remarkConditional() {
        Order order = createTestOrder();
        String template = "{if:备注}备注: {备注}{/if}\n{if:备注}有备注行{/if}";
        String ticket = renderOrderRaw(template, order);
        assertTrue(ticket.contains("备注: 少油少盐"));
        assertTrue(ticket.contains("有备注行"));

        order.setRemark(null);
        ticket = renderOrderRaw(template, order);
        assertFalse(ticket.contains("备注"));
        assertFalse(ticket.contains("有备注行"));
    }

    @Test
    void testIfBlock_nestedAndNotEquals() {
        Order order = createTestOrder();
        String ticket = renderOrderRaw(
                "{if:用餐方式!=外卖}堂食或打包{if:桌号} 台号:{桌号}{/if}{/if}",
                order);
        assertTrue(ticket.contains("堂食或打包"));
        assertTrue(ticket.contains("台号:A08"));

        order.setDineInOrTakeOut("外卖");
        ticket = renderOrderRaw(
                "{if:用餐方式!=外卖}堂食或打包{else}外卖单{/if}",
                order);
        assertFalse(ticket.contains("堂食或打包"));
        assertTrue(ticket.contains("外卖单"));
    }

    @Test
    void testIfBlock_emptyConditionHides() {
        Order order = createTestOrder();
        String ticket = renderOrderRaw("{if:}空条件{/if}\n正常行", order);
        assertFalse(ticket.contains("空条件"));
        assertTrue(ticket.contains("正常行"));
    }


    @Test
    void testDishNameShortenedToFourCharsAndSpecParensStripped() {
        // 需求回归：菜品名统一 4 字以内（8 字节），去掉名称后的括号规格内容
        Order order = createTestOrder(); // 特色油边(微辣) / 秘制羊肉串(中辣)
        String ticket = engine.renderReceiptTicket(order, false, PrintTemplateOptions.defaultOptions());
        // 4 字内菜名保持原样，且不再拼接括号规格
        assertTrue(ticket.contains("特色油边"));
        assertFalse(ticket.contains("(微辣)"));
        // 5 字菜名截断为 4 字
        assertTrue(ticket.contains("秘制羊肉"));
        assertFalse(ticket.contains("秘制羊肉串"));
        assertFalse(ticket.contains("(中辣)"));
    }
    // ===== 回归：备注为空时整行不打印（raw 与 BLOCK 均不输出"备注: "空标签） =====
    @Test
    void testRemarkEmpty_hidesRawLine() {
        Order order = createTestOrder();
        String ticket = renderOrderRaw("备注: {备注}", order);
        assertTrue(ticket.contains("备注: 少油少盐"));

        order.setRemark(null);
        ticket = renderOrderRaw("第一行\n备注: {备注}\n第二行", order);
        assertTrue(ticket.contains("第一行"));
        assertTrue(ticket.contains("第二行"));
        assertFalse(ticket.contains("备注"));
    }

    @Test
    void testRemarkEmpty_hidesBlockCustomText() {
        Order order = createTestOrder();
        com.lanf.printing.model.PrintTemplateDsl dsl = engine.buildDefaultDsl("ORDER", "58mm");
        com.lanf.printing.model.PrintTemplateDsl.TemplateBlock custom = new com.lanf.printing.model.PrintTemplateDsl.TemplateBlock();
        custom.setId("block_custom_remark");
        custom.setType("CUSTOM_TEXT");
        custom.setEnabled(true);
        java.util.Map<String, Object> cfg = new java.util.LinkedHashMap<>();
        cfg.put("content", "备注: {备注}");
        custom.setConfig(cfg);
        dsl.getBlocks().add(custom);

        order.setRemark(null);
        String ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertFalse(ticket.contains("备注"));
        assertFalse(ticket.contains("__PRINT_BINDING_MISSING__"));

        order.setRemark("不要香菜");
        ticket = engine.renderDynamicTicket(order, dsl, PrintTemplateOptions.defaultOptions());
        assertTrue(ticket.contains("备注: 不要香菜"));
    }
    @Test
    void testIfBlock_remarkVarWithBraces() {
        // {if:{备注}} 带花括号变量名写法：备注非空显示整段，空则整段隐藏（含 else 空分支与分隔线）
        Order order = createTestOrder();
        String tpl = "{if:{备注}}备注：{备注}\n{else}{/if}";
        String ticket = renderOrderRaw(tpl, order);
        assertTrue(ticket.contains("备注：少油少盐"));
        assertFalse(ticket.contains("}"));

        order.setRemark(null);
        ticket = renderOrderRaw(tpl, order);
        assertFalse(ticket.contains("备注"));
        assertFalse(ticket.contains("}"));
    }
    @Test
    void testRawFeieRules_brNotDuplicated() {
        // 前端按 demo 形式传飞鹅原始数据：<BR> 分隔行，后端直接按飞鹅规则解析，不重复追加换行
        Order order = createTestOrder();
        String tpl = "<CB>老肥油边王</CB><BR>名称　　　　　 单价  数量  金额<BR>备注：{备注}<BR><QR>https://u.wechat.com/x</QR>";
        String ticket = renderOrderRaw(tpl, order);
        assertFalse(ticket.contains("</CB><BR><BR>"), "标签行不应出现重复换行");
        assertFalse(ticket.contains("金额<BR><BR>"), "数据行不应出现重复换行");
        assertTrue(ticket.contains("<CB>老肥油边王</CB><BR>"));
        assertTrue(ticket.contains("备注：少油少盐<BR>"));
        assertTrue(ticket.contains("<QR>https://u.wechat.com/x</QR><BR>"));
    }

    @Test
    void testRawFeieRules_mixedBrAndNewline() {
        // 混合 <BR> 与 \n 分隔：统一归一为换行，按飞鹅规则输出
        Order order = createTestOrder();
        String tpl = "<CB>结账单</CB>\n名称 单价 数量 金额<BR>备注：{备注}\n<CUT>";
        String ticket = renderOrderRaw(tpl, order);
        assertFalse(ticket.contains("</CB><BR><BR>"));
        assertFalse(ticket.contains("金额<BR><BR>"));
        assertTrue(ticket.contains("<CB>结账单</CB><BR>"));
        assertTrue(ticket.contains("备注：少油少盐<BR>"));
        assertTrue(ticket.contains("<CUT>"));
    }
    @Test
    void testCustomContent_feieRulesParsed() {
        // 前端直传原始数据：if 条件块保留解析 + <BR> 归一 + 变量插值 + 标签透传
        Order order = createTestOrder(); // 堂食, 桌号 A08
        com.lanf.printing.model.PrintContext ctx = com.lanf.printing.model.PrintContext.ofOrder(order, false);
        String tpl = "<CB>点餐单</CB><BR>{if:用餐方式=堂食}台号：{桌号}{else}取餐码：{取餐码}{/if}<BR>备注：{备注}<BR><CUT>";
        String out = engine.renderCustomContent("ORDER", ctx, tpl, PrintTemplateOptions.defaultOptions());
        assertTrue(out.contains("<CB>点餐单</CB><BR>"));
        assertTrue(out.contains("台号：A08<BR>"));
        assertFalse(out.contains("取餐码"));
        assertTrue(out.contains("备注：少油少盐<BR>"));
        assertFalse(out.contains("<BR><BR>"));
        assertTrue(out.contains("<CUT>"));
    }

    @Test
    void testCustomContent_newlineNormalizedToBr() {
        // 前端传 \n 分隔（飞鹅只认 <BR> 换行）：归一为 <BR>
        com.lanf.printing.model.PrintContext ctx = com.lanf.printing.model.PrintContext.ofCustom(1, "ORDER", null);
        String out = engine.renderCustomContent("ORDER", ctx, "第一行\n第二行", PrintTemplateOptions.defaultOptions());
        assertEquals("第一行<BR>第二行<BR>", out);
    }
}
