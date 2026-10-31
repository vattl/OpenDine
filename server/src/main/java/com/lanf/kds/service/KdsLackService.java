package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.mapper.DishShopMapper;
import com.lanf.order.OrderDetailQuantityParser;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import com.lanf.service.IOperationLogService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.impl.OrderDetailRefundService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.HashMap;
import java.util.Map;

@Service
public class KdsLackService {

    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IDishService dishService;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private IOperationLogService operationLogService;
    @Autowired
    private DishMenuPushService dishMenuPushService;
    @Autowired
    private OrderDetailRefundService refundService;

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> reportLack(int shopId, int detailId, String screenTag, String remark) {
        return reportLack(shopId, detailId, null, screenTag, remark, true);
    }

    /**
     * 缺货：回写点餐明细（退菜/减量）、作废 KDS 工单，并按门店配置联动售罄。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> reportLack(int shopId, int detailId, Integer quantity, String screenTag,
                                          String remark, boolean applySoldOut) {
        OrderDetail detail = requireDetail(detailId);
        Order order = requireOrder(detail);
        Dish dish = resolveDish(detail);
        int refundQty = resolveRefundQty(detail, quantity);
        refundToOrdering(order, detail, refundQty);
        boolean setSoldOut = applySoldOut && shouldSetSoldOut(shopId);
        if (setSoldOut && dish != null && dish.getId() != null) {
            markDishSoldOut(shopId, dish);
        }
        logAction(shopId, detailId, dish, screenTag, remark, "item_lack", refundQty);
        Map<String, Object> result = new HashMap<>();
        result.put("detail_id", detailId);
        result.put("refund_quantity", refundQty);
        result.put("sold_out_applied", setSoldOut && dish != null);
        result.put("dish_id", dish != null ? dish.getId() : null);
        result.put("line_status", detail.getLine_status());
        return result;
    }

    /**
     * 退菜：同步点餐系统并作废 KDS 工单（不默认联动售罄，除非显式 sold_out=1）。
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> refundDish(int shopId, int detailId, Integer quantity, String screenTag, String remark) {
        return refundDish(shopId, detailId, quantity, screenTag, remark, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> refundDish(int shopId, int detailId, Integer quantity, String screenTag,
                                            String remark, boolean applySoldOut) {
        OrderDetail detail = requireDetail(detailId);
        Order order = requireOrder(detail);
        Dish dish = resolveDish(detail);
        int refundQty = resolveRefundQty(detail, quantity);
        refundToOrdering(order, detail, refundQty);
        boolean setSoldOut = applySoldOut && shouldSetSoldOut(shopId);
        if (setSoldOut && dish != null && dish.getId() != null) {
            markDishSoldOut(shopId, dish);
        }
        logAction(shopId, detailId, dish, screenTag, remark, "item_refund", refundQty);
        Map<String, Object> result = new HashMap<>();
        result.put("detail_id", detailId);
        result.put("refund_quantity", refundQty);
        result.put("sold_out_applied", setSoldOut && dish != null);
        result.put("dish_id", dish != null ? dish.getId() : null);
        result.put("line_status", detail.getLine_status());
        return result;
    }

    private void refundToOrdering(Order order, OrderDetail detail, int refundQty) {
        int currentQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
        if (refundQty >= currentQty) {
            refundService.refundFullLine(detail, order);
        } else {
            refundService.refundPartial(detail, order, refundQty);
        }
        OrderDetail fresh = orderDetailService.getById(detail.getId());
        if (fresh != null) {
            detail.setQuantity(fresh.getQuantity());
            detail.setLine_status(fresh.getLine_status());
            detail.setTotal_price(fresh.getTotal_price());
        }
    }

    private static int resolveRefundQty(OrderDetail detail, Integer quantity) {
        int currentQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
        if (quantity == null || quantity <= 0 || quantity >= currentQty) {
            return currentQty;
        }
        return quantity;
    }

    private boolean shouldSetSoldOut(int shopId) {
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        return cfg.getLack_sets_sold_out() != null && cfg.getLack_sets_sold_out() == 1;
    }

    private OrderDetail requireDetail(int detailId) {
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null) {
            throw new IllegalArgumentException("明细不存在");
        }
        return detail;
    }

    private Order requireOrder(OrderDetail detail) {
        Order order = orderService.getById(detail.getMId());
        if (order == null) {
            throw new IllegalArgumentException("订单不存在");
        }
        return order;
    }

    private Dish resolveDish(OrderDetail detail) {
        if (!StringUtils.hasText(detail.getName())) {
            return null;
        }
        return dishService.getOne(new QueryWrapper<Dish>().eq("name", detail.getName().trim()).last("LIMIT 1"));
    }

    private void markDishSoldOut(int shopId, Dish dish) {
        DishShop ds = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("dish_id", dish.getId())
                .last("LIMIT 1"));
        if (ds != null) {
            dishShopMapper.update(null, new UpdateWrapper<DishShop>()
                    .eq("shop_id", shopId)
                    .eq("dish_id", dish.getId())
                    .set("stock", 0)
                    .set("stock_enabled", 1)
                    .set("sold_out", 1));
            dishMenuPushService.notifyCatalogChanged("kds_lack", dish.getId(), dish.getName(), dish.isOnsale());
        } else {
            dish.setStock(0);
            dish.setSold_out(1);
            dishService.updateById(dish);
            dishMenuPushService.notifyCatalogChanged("kds_lack", dish.getId(), dish.getName(), dish.isOnsale());
        }
    }

    private void logAction(int shopId, int detailId, Dish dish, String screenTag, String remark,
                           String action, int refundQty) {
        String snapshot = "{\"detail_id\":" + detailId + ",\"dish_id\":" + (dish != null ? dish.getId() : "null")
                + ",\"screen_tag\":\"" + (screenTag != null ? screenTag : "") + "\",\"remark\":\""
                + (remark != null ? remark.replace("\"", "'") : "") + "\",\"refund_quantity\":" + refundQty + "}";
        operationLogService.recordSystem(shopId, "kds", action, String.valueOf(detailId), snapshot);
    }
}
