package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.DishStockLog;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.DishStockLogMapper;
import com.lanf.order.OrderDetailQuantityParser;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.order.RefundStockAction;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class DishShopStockServiceImpl implements IDishShopStockService {

    private static final Logger log = LoggerFactory.getLogger(DishShopStockServiceImpl.class);

    @Autowired
    private IDishService dishService;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired(required = false)
    private DishStockLogMapper dishStockLogMapper;
    @Autowired
    private DishMenuPushService dishMenuPushService;

    @Override
    public void validateCanDeduct(List<OrderDetail> lines, Integer shopId) {
        Map<Integer, Integer> agg = aggregateQuantities(lines, shopId);
        for (Map.Entry<Integer, Integer> e : agg.entrySet()) {
            Dish dish = dishService.getById(e.getKey());
            if (dish == null) {
                throw new RuntimeException("菜品不存在，请刷新菜单后重试");
            }
            StockRef ref = resolveStockRef(shopId, dish.getId(), dish);
            if (!ref.tracked) {
                continue;
            }
            int need = e.getValue();
            int have = ref.stock != null ? ref.stock : 0;
            if (have < need) {
                throw new RuntimeException("菜品「" + dish.getName() + "」库存不足（剩余 " + have + " 份，需 " + need + " 份）");
            }
        }
    }

    @Override
    public void deductForDetails(List<OrderDetail> lines, Integer shopId) {
        Map<Integer, Integer> agg = aggregateQuantities(lines, shopId);
        for (Map.Entry<Integer, Integer> e : agg.entrySet()) {
            deductQuantityInternal(shopId, e.getKey(), e.getValue());
        }
    }

    @Override
    public void restoreForDetail(OrderDetail detail, Integer shopId) {
        handleRefundStock(detail, shopId, OrderDetailQuantityParser.parseQuantityOrZero(detail != null ? detail.getQuantity() : null),
                RefundStockAction.RESTORE, null, "整行退菜或取消单");
    }

    @Override
    public void restoreQuantity(OrderDetail detail, Integer shopId, int quantity) {
        handleRefundStock(detail, shopId, quantity, RefundStockAction.RESTORE, null, "部分退菜或减量");
    }

    @Override
    public void deductQuantity(OrderDetail detail, Integer shopId, int quantity) {
        if (quantity <= 0 || !OrderDetailQueryHelper.countsForShopStock(detail)) {
            return;
        }
        Dish dish = resolveDishForDetail(detail);
        if (dish == null || dish.getId() == null) {
            return;
        }
        deductQuantityInternal(shopId, dish.getId(), quantity);
    }

    @Override
    public void handleRefundStock(OrderDetail detail, Integer shopId, int quantity,
                                  RefundStockAction stockAction, String operator, String remark) {
        if (quantity <= 0 || !OrderDetailQueryHelper.countsForShopStock(detail)) {
            return;
        }
        if (stockAction == null) {
            stockAction = RefundStockAction.RESTORE;
        }
        Dish dish = resolveDishForDetail(detail);
        if (dish == null || dish.getId() == null) {
            log.warn("退菜库存处理跳过：明细 id={} name={} 无法匹配菜品", detail.getId(), detail.getName());
            return;
        }
        StockRef ref;
        try {
            ref = resolveStockRef(shopId, dish.getId(), dish);
        } catch (RuntimeException ex) {
            log.warn("退菜库存处理跳过：明细 id={} dishId={} shopId={}：{}",
                    detail.getId(), dish.getId(), shopId, ex.getMessage());
            return;
        }
        if (!ref.tracked) {
            return;
        }

        int beforeStock = ref.stock != null ? ref.stock : 0;
        String orderNo = detail.getMorder_no();
        Integer detailId = detail.getId();

        switch (stockAction) {
            case RESTORE: {
                int afterStock = beforeStock + quantity;
                dishShopMapper.update(null, new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<DishShop>()
                        .setSql("sold_out = CASE WHEN stock + " + quantity + " > 0 THEN 0 ELSE sold_out END")
                        .setSql("stock = stock + " + quantity)
                        .eq("shop_id", ref.shopId)
                        .eq("dish_id", dish.getId()));
                notifyIfRestored(shopId, dish);
                recordStockLog(shopId, dish.getId(), dish.getName(), orderNo, detailId,
                        "REFUND_RESTORE", quantity, beforeStock, afterStock, operator, remark);
                break;
            }
            case NO_RESTORE: {
                recordStockLog(shopId, dish.getId(), dish.getName(), orderNo, detailId,
                        "REFUND_NO_RESTORE", 0, beforeStock, beforeStock, operator, remark);
                break;
            }
            case OUT_OF_STOCK: {
                dishShopMapper.update(null, new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<DishShop>()
                        .set("stock", 0)
                        .set("stock_enabled", 1)
                        .set("sold_out", 1)
                        .eq("shop_id", ref.shopId)
                        .eq("dish_id", dish.getId()));
                dishMenuPushService.notifyCatalogChanged("stock_sold_out", dish.getId(), dish.getName(), dish.isOnsale());
                recordStockLog(shopId, dish.getId(), dish.getName(), orderNo, detailId,
                        "REFUND_OUT_OF_STOCK", -beforeStock, beforeStock, 0, operator, remark);
                break;
            }
        }
    }

    private void deductQuantityInternal(Integer shopId, int dishId, int dec) {
        Dish d = dishService.getById(dishId);
        if (d == null) {
            return;
        }
        StockRef ref = resolveStockRef(shopId, dishId, d);
        if (!ref.tracked) {
            return;
        }
        int beforeStock = ref.stock != null ? ref.stock : 0;
        int afterStock = beforeStock - dec;
        boolean updated = dishShopMapper.update(null, new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<DishShop>()
                .setSql("sold_out = CASE WHEN stock - " + dec + " <= 0 THEN 1 ELSE sold_out END")
                .setSql("stock = stock - " + dec)
                .eq("shop_id", ref.shopId)
                .eq("dish_id", dishId)
                .ge("stock", dec)) > 0;
        if (!updated) {
            throw new RuntimeException("菜品「" + d.getName() + "」库存不足，请刷新后再试");
        }
        recordStockLog(shopId, dishId, d.getName(), null, null,
                "ORDER_DEDUCT", -dec, beforeStock, afterStock, null, null);
        Dish after = dishService.getById(dishId);
        if (after != null) {
            StockRef afterRef = resolveStockRef(shopId, dishId, after);
            if (afterRef.stock != null && afterRef.stock <= 0) {
                dishMenuPushService.notifyCatalogChanged("stock_sold_out", after.getId(), after.getName(), after.isOnsale());
            }
        }
    }

    private void notifyIfRestored(Integer shopId, Dish dish) {
        Dish after = dishService.getById(dish.getId());
        if (after == null) {
            return;
        }
        StockRef afterRef = resolveStockRef(shopId, dish.getId(), after);
        if (!afterRef.tracked) {
            return;
        }
        dishMenuPushService.notifyCatalogChanged("stock_restored", after.getId(), after.getName(), after.isOnsale());
    }

    private void recordStockLog(Integer shopId, Integer dishId, String dishName, String orderNo,
                                Integer detailId, String changeType, int delta, Integer beforeStock,
                                Integer afterStock, String operator, String remark) {
        if (dishStockLogMapper == null) {
            return;
        }
        try {
            DishStockLog entity = new DishStockLog();
            entity.setShop_id(shopId);
            entity.setDish_id(dishId);
            entity.setDish_name(dishName);
            entity.setOrder_no(orderNo);
            entity.setDetail_id(detailId);
            entity.setChange_type(changeType);
            entity.setDelta(delta);
            entity.setStock_before(beforeStock);
            entity.setStock_after(afterStock);
            entity.setOperator_id(operator);
            entity.setRemark(remark);
            entity.setCreated_at(new Date());
            dishStockLogMapper.insert(entity);
        } catch (Exception e) {
            log.warn("记录库存变动流水日志异常: err={}", e.getMessage());
        }
    }

    private Map<Integer, Integer> aggregateQuantities(List<OrderDetail> lines, Integer shopId) {
        Map<Integer, Integer> map = new HashMap<>();
        if (lines == null) {
            return map;
        }
        for (OrderDetail od : lines) {
            if (!OrderDetailQueryHelper.countsForShopStock(od)) {
                continue;
            }
            Dish dish = od.getDish_id() != null
                    ? dishService.getById(od.getDish_id()) : resolveDishByMenuName(od.getName());
            if (dish == null || dish.getId() == null) {
                continue;
            }
            StockRef ref = resolveStockRef(shopId, dish.getId(), dish);
            if (!ref.tracked) {
                continue;
            }
            int q = OrderDetailQuantityParser.parsePositive(od.getQuantity());
            map.merge(dish.getId(), q, Integer::sum);
        }
        return map;
    }

    /**
     * 与扣减侧（{@link #aggregateQuantities}）对齐：优先按明细 dish_id 精确匹配，
     * 查不到再按名称反查（兼容历史无 dish_id 的明细）。
     */
    private Dish resolveDishForDetail(OrderDetail detail) {
        if (detail == null) {
            return null;
        }
        if (detail.getDish_id() != null) {
            Dish byId = dishService.getById(detail.getDish_id());
            if (byId != null) {
                return byId;
            }
        }
        return resolveDishByMenuName(detail.getName());
    }

    private Dish resolveDishByMenuName(String dishName) {
        if (!StringUtils.hasText(dishName)) {
            return null;
        }
        String name = dishName.trim();
        Dish dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                .eq(Dish::getName, name)
                .last("LIMIT 1"));
        if (dish == null) {
            String compact = name.replaceAll("\\s+", "");
            if (!compact.equals(name)) {
                dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                        .eq(Dish::getName, compact)
                        .last("LIMIT 1"));
            }
        }
        return dish;
    }

    private static boolean isStockTrackedByValue(Integer stock, boolean onsale) {
        if (stock == null || stock < 0) {
            return false;
        }
        if (stock > 0) {
            return true;
        }
        return !onsale;
    }

    private StockRef resolveStockRef(Integer shopId, Integer dishId, Dish dish) {
        if (shopId == null) {
            throw new RuntimeException("订单缺少门店ID，无法执行门店库存操作");
        }
        if (dishId == null || dish == null) {
            throw new RuntimeException("菜品信息缺失，无法执行门店库存操作");
        }
        DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("dish_id", dishId)
                .last("LIMIT 1"));
        if (link == null) {
            throw new RuntimeException("菜品「" + dish.getName() + "」未挂到当前门店，无法执行库存操作");
        }
        if (link.getStock() == null) {
            throw new RuntimeException("菜品「" + dish.getName() + "」门店库存未配置");
        }
        Integer s = link.getStock();
        boolean effectiveOnsale = link.getOnsale_override() != null ? link.getOnsale_override() == 1 : dish.isOnsale();
        // 是否跟踪库存以持久标志为准（docs/db_migration_dish_shop_stock_enabled.sql），
        // 不再依赖当前 stock 值推断——否则库存被扣到 0 后会被误判为「未启用」导致退菜无法回退。
        // 迁移未执行（标志为 null）时回退旧启发式，保持兼容。
        boolean tracked = link.getStock_enabled() != null
                ? link.getStock_enabled() == 1
                : isStockTrackedByValue(s, effectiveOnsale);
        return new StockRef(shopId, dishId, tracked, s);
    }

    private static final class StockRef {
        final Integer shopId;
        final Integer dishId;
        final boolean tracked;
        final Integer stock;

        StockRef(Integer shopId, Integer dishId, boolean tracked, Integer stock) {
            this.shopId = shopId;
            this.dishId = dishId;
            this.tracked = tracked;
            this.stock = stock;
        }
    }
}
