package com.lanf.printing.model;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import lombok.Data;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/**
 * 统一打印上下文对象（封装业务出票所需数据）
 */
@Data
public class PrintContext {

    private Integer shopId;
    private String scenario;

    /** 订单数据（可选） */
    private Order order;

    /** 订单单条明细（针对传菜、标签等） */
    private OrderDetail orderDetail;

    /** 传菜或出餐数量 */
    private Integer serveQty;

    /** 后厨分单分类过滤（可选） */
    private Set<String> cidFilter;

    /** 是否为加菜单格式（前台小票：true=加菜单/制作联，false=结账单/预结单） */
    private boolean addDishes;

    /** 收银交接班数据（可选） */
    private Shift shift;

    /** 自定义打印文本内容（若指定则优先使用该内容，跳过模板渲染） */
    private String customContent;

    /** 操作人 ID（可选） */
    private Integer adminId;

    /** 附加参数 Map */
    private Map<String, Object> extra = new LinkedHashMap<>();

    public static PrintContext ofOrder(Order order, boolean isAddDishes) {
        PrintContext ctx = new PrintContext();
        if (order != null) {
            ctx.setShopId(order.getShop_id());
        }
        ctx.setOrder(order);
        ctx.setAddDishes(isAddDishes);
        ctx.setScenario(PrintScenario.resolveDispatchCode(PrintScenario.ORDER, ctx));
        return ctx;
    }

    public static PrintContext ofKitchen(Order order, Set<String> cidFilter) {
        PrintContext ctx = new PrintContext();
        if (order != null) {
            ctx.setShopId(order.getShop_id());
        }
        ctx.setScenario(PrintScenario.KITCHEN);
        ctx.setOrder(order);
        ctx.setCidFilter(cidFilter != null ? cidFilter : Collections.emptySet());
        return ctx;
    }

    public static PrintContext ofServe(Order order, OrderDetail detail, int serveQty) {
        PrintContext ctx = new PrintContext();
        if (order != null) {
            ctx.setShopId(order.getShop_id());
        }
        ctx.setScenario(PrintScenario.EXPEDITE);
        ctx.setOrder(order);
        ctx.setOrderDetail(detail);
        ctx.setServeQty(serveQty);
        // 业务溯源：供 t_printing_job 记录（biz_type/biz_id），便于按明细/订单反查打印记录
        ctx.getExtra().put("bizType", "kds_serve");
        if (detail != null && detail.getId() != null) {
            ctx.getExtra().put("bizId", detail.getId().longValue());
        }
        if (order != null && order.getId() != null) {
            ctx.getExtra().put("orderId", order.getId().longValue());
        }
        return ctx;
    }

    public static PrintContext ofShift(Shift shift, Map<String, Object> stats) {
        PrintContext ctx = new PrintContext();
        if (shift != null) {
            ctx.setShopId(shift.getShop_id());
            ctx.setAdminId(shift.getAdmin_id());
        }
        ctx.setScenario(PrintScenario.SHIFT);
        ctx.setShift(shift);
        if (stats != null) {
            ctx.getExtra().putAll(stats);
        }
        return ctx;
    }

    public static PrintContext ofRefund(Order order, Map<String, Object> refundInfo) {
        PrintContext ctx = new PrintContext();
        if (order != null) {
            ctx.setShopId(order.getShop_id());
        }
        ctx.setScenario(PrintScenario.REFUND);
        ctx.setOrder(order);
        if (refundInfo != null) {
            ctx.getExtra().putAll(refundInfo);
        }
        return ctx;
    }

    public static PrintContext ofCustom(int shopId, String scenario, String customContent) {
        PrintContext ctx = new PrintContext();
        ctx.setShopId(shopId);
        ctx.setScenario(scenario);
        ctx.setCustomContent(customContent);
        return ctx;
    }
}
