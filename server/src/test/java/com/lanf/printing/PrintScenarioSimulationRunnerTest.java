package com.lanf.printing;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.printing.engine.PrintTemplateEngineImpl;
import com.lanf.printing.engine.PrintTemplateOptions;
import com.lanf.printing.engine.PrintTicketParser;
import com.lanf.printing.model.PrintTemplateDsl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.*;

import static org.junit.jupiter.api.Assertions.assertNotNull;

public class PrintScenarioSimulationRunnerTest {

    private PrintTemplateEngineImpl engine;

    @BeforeEach
    void setUp() {
        engine = new PrintTemplateEngineImpl();
    }

    private Order createDineInOrder() {
        Order order = new Order();
        order.setId(2001);
        order.setShop_id(1);
        order.setOrder_no("ORD-DINEIN-20260902-001");
        order.setTable_number("A08");
        order.setDineInOrTakeOut("堂食");
        order.setNumber_of_diners("4");
        order.setOrder_time(new Date());
        order.setPay_time(new Date());
        order.setTransac_status("success");
        order.setSett_amount(158.0);
        order.setDiscount_amount(10.0);
        order.setService_fee(0.0);
        order.setPayment_method("微信支付");
        order.setRemark("微辣，少放香菜，快点上");

        List<OrderDetail> items = new ArrayList<>();

        OrderDetail d1 = new OrderDetail();
        d1.setId(101);
        d1.setName("招牌特色油边");
        d1.setCid("1"); // 烧烤类
        d1.setQuantity("4");
        d1.setTotal_price(48.0);
        d1.setSelectedSpicy("{\"辣度\":\"微辣\",\"备注\":\"烤焦一点\"}");
        items.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(102);
        d2.setName("碳烤鲜羊肉串");
        d2.setCid("1"); // 烧烤类
        d2.setQuantity("10");
        d2.setTotal_price(35.0);
        d2.setSelectedSpicy("{\"辣度\":\"微辣\"}");
        items.add(d2);

        OrderDetail d3 = new OrderDetail();
        d3.setId(103);
        d3.setName("锡纸金针菇");
        d3.setCid("2"); // 锡纸类
        d3.setQuantity("1");
        d3.setTotal_price(18.0);
        d3.setSelectedSpicy("{\"辣度\":\"不辣\"}");
        items.add(d3);

        OrderDetail d4 = new OrderDetail();
        d4.setId(104);
        d4.setName("冰镇原浆啤酒");
        d4.setCid("3"); // 酒水饮料
        d4.setQuantity("2");
        d4.setTotal_price(30.0);
        items.add(d4);

        order.setGoods_list(items);
        return order;
    }

    private Order createTakeawayOrder() {
        Order order = new Order();
        order.setId(2002);
        order.setShop_id(1);
        order.setOrder_no("ORD-PACK-20260902-002");
        order.setTable_number("自提03号");
        order.setDineInOrTakeOut("打包");
        order.setOrder_time(new Date());
        order.setPay_time(new Date());
        order.setTransac_status("success");
        order.setSett_amount(70.0);
        order.setDiscount_amount(0.0);
        order.setPayment_method("支付宝");
        order.setRemark("打包带走，多给两副筷子");

        List<OrderDetail> items = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(201);
        d1.setName("特色烤冷面");
        d1.setCid("4"); // 主食
        d1.setQuantity("2");
        d1.setTotal_price(24.0);
        d1.setSelectedSpicy("{\"辣度\":\"酸甜微辣\",\"加料\":[\"加蛋\",\"加肠\"]}");
        items.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(202);
        d2.setName("秘制烤鸡翅");
        d2.setCid("1"); // 烧烤类
        d2.setQuantity("4");
        d2.setTotal_price(44.0);
        d2.setSelectedSpicy("{\"辣度\":\"蜜汁\"}");
        items.add(d2);

        order.setGoods_list(items);
        return order;
    }

    private Order createTakeoutDeliveryOrder() {
        Order order = new Order();
        order.setId(2003);
        order.setShop_id(1);
        order.setOrder_no("WM2026090299881");
        order.setTable_number("外卖#06");
        order.setDineInOrTakeOut("外卖");
        order.setOrder_time(new Date());
        order.setPay_time(new Date());
        order.setTransac_status("success");
        order.setDiscount_amount(15.0);
        order.setSett_amount(108.0);
        order.setPayment_method("微信小程序支付");
        order.setRemark("【配送地址: 阳光花园二期8栋1202室 (王先生 138****5678)】放在门口鞋柜上，敲下门就行");

        List<OrderDetail> items = new ArrayList<>();
        OrderDetail d1 = new OrderDetail();
        d1.setId(301);
        d1.setName("招牌特色油边");
        d1.setCid("1");
        d1.setQuantity("5");
        d1.setTotal_price(60.0);
        d1.setSelectedSpicy("{\"辣度\":\"中辣\"}");
        items.add(d1);

        OrderDetail d2 = new OrderDetail();
        d2.setId(302);
        d2.setName("蒜蓉烤大虾");
        d2.setCid("1");
        d2.setQuantity("5");
        d2.setTotal_price(35.0);
        items.add(d2);

        OrderDetail d3 = new OrderDetail();
        d3.setId(303);
        d3.setName("冰镇原浆啤酒");
        d3.setCid("3");
        d3.setQuantity("1");
        d3.setTotal_price(15.0);
        items.add(d3);

        OrderDetail d4 = new OrderDetail();
        d4.setId(304);
        d4.setName("精致餐具与打包袋");
        d4.setCid("5");
        d4.setQuantity("2");
        d4.setTotal_price(5.0);
        items.add(d4);

        order.setGoods_list(items);
        return order;
    }

    @Test
    void simulateAllScenarios() {
        PrintTemplateOptions options = PrintTemplateOptions.defaultOptions();
        options.setBrandHeader("老肥油边王(旗舰店)");

        System.out.println("===============================================================");
        System.out.println(">>> 场景一：【堂食订单】出票流程模拟");
        System.out.println("===============================================================");
        Order dineInOrder = createDineInOrder();

        // 1. 前台结账单 / 客户联
        PrintTemplateDsl checkoutDsl = engine.buildDefaultDsl("CHECKOUT", "58mm");
        String checkoutTicket = engine.renderDynamicTicket(dineInOrder, checkoutDsl, options);
        System.out.println("\n--- 1.1 前台结账单 (CHECKOUT) ---");
        System.out.println(PrintTicketParser.toPlainText(checkoutTicket));
        System.out.println("【飞鹅云指令原始数据】：\n" + checkoutTicket);

        // 2. 后厨制作单 (分单打印)
        PrintTemplateDsl kitchenDsl = engine.buildDefaultDsl("KITCHEN", "58mm");
        List<String> kitchenTickets = engine.renderDynamicKitchenTickets(dineInOrder, kitchenDsl, null, options);
        System.out.println("\n--- 1.2 后厨制作单 (KITCHEN - 档口制作联) ---");
        for (int i = 0; i < kitchenTickets.size(); i++) {
            System.out.println(">> 制作分单 #" + (i + 1) + ":");
            System.out.println(PrintTicketParser.toPlainText(kitchenTickets.get(i)));
        }

        // 3. 传菜单 (KDS 划菜)
        PrintTemplateDsl expediteDsl = engine.buildDefaultDsl("EXPEDITE", "58mm");
        OrderDetail expediteItem = dineInOrder.getGoods_list().get(0);
        String expediteTicket = engine.renderDynamicServeTicket(dineInOrder, expediteItem, 4, expediteDsl, options);
        System.out.println("\n--- 1.3 KDS 划菜传菜单 (EXPEDITE) ---");
        System.out.println(PrintTicketParser.toPlainText(expediteTicket));

        System.out.println("\n===============================================================");
        System.out.println(">>> 场景二：【收银打包/到店自提】出票流程模拟");
        System.out.println("===============================================================");
        Order packOrder = createTakeawayOrder();

        // 1. 前台整单 (FULL_ORDER 带打包费与打包标识)
        PrintTemplateDsl fullOrderDsl = engine.buildDefaultDsl("FULL_ORDER", "58mm");
        String packTicket = engine.renderDynamicTicket(packOrder, fullOrderDsl, options);
        System.out.println("\n--- 2.1 打包结账单 (FULL_ORDER) ---");
        System.out.println(PrintTicketParser.toPlainText(packTicket));

        // 2. 后厨单
        List<String> packKitchen = engine.renderDynamicKitchenTickets(packOrder, kitchenDsl, null, options);
        System.out.println("\n--- 2.2 打包后厨单 (KITCHEN) ---");
        System.out.println(PrintTicketParser.toPlainText(packKitchen.get(0)));

        System.out.println("\n===============================================================");
        System.out.println(">>> 场景三：【外卖配送】出票流程模拟");
        System.out.println("===============================================================");
        Order takeoutOrder = createTakeoutDeliveryOrder();

        // 1. 外卖配送联 (TAKEOUT - 含骑手信息、配送地址、顾客电话)
        PrintTemplateDsl takeoutDsl = engine.buildDefaultDsl("TAKEOUT", "58mm");
        String takeoutTicket = engine.renderDynamicTicket(takeoutOrder, takeoutDsl, options);
        System.out.println("\n--- 3.1 外卖配送小票 (TAKEOUT) ---");
        System.out.println(PrintTicketParser.toPlainText(takeoutTicket));
        System.out.println("【飞鹅云指令原始数据】：\n" + takeoutTicket);

        // 2. 外卖后厨备餐单
        List<String> takeoutKitchen = engine.renderDynamicKitchenTickets(takeoutOrder, kitchenDsl, null, options);
        System.out.println("\n--- 3.2 外卖后厨备餐单 (KITCHEN) ---");
        System.out.println(PrintTicketParser.toPlainText(takeoutKitchen.get(0)));

        assertNotNull(checkoutTicket);
        assertNotNull(packTicket);
        assertNotNull(takeoutTicket);
    }
}
