package com.lanf.kds.service;

import com.lanf.entity.Dish;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import com.lanf.util.AfterCommitExecutor;

/** Applies cashier-authoritative availability strictly to the current shop row. */
@Service
public class KdsDishAvailabilityService {
    private final JdbcTemplate jdbc;
    private final IDishService dishService;
    private final DishMenuPushService pushService;

    public KdsDishAvailabilityService(JdbcTemplate jdbc, IDishService dishService, DishMenuPushService pushService) {
        this.jdbc = jdbc;
        this.dishService = dishService;
        this.pushService = pushService;
    }

    public void applySnapshot(int shopId, int dishId, Integer stock, Integer soldOut, String operationType) {
        // 明确售罄优先于快照中的旧库存值，避免出现 sold_out=1、stock>0 的矛盾状态。
        Integer normalizedStock = Integer.valueOf(1).equals(soldOut) ? Integer.valueOf(0) : stock;
        // stock=-1 为「不限量」哨兵：不可能售罄，sold_out 归 0；stock=0 售罄；stock>0 可售
        Integer normalizedSoldOut = normalizedStock != null
                ? (normalizedStock == 0 ? 1 : 0)
                : soldOut;
        // 快照带库存值即视为启用库存跟踪；不带库存值（null）保持原标志不变
        Integer stockEnabled = normalizedStock != null ? (normalizedStock >= 0 ? 1 : 0) : null;
        jdbc.update("INSERT IGNORE INTO t_dish_shop (shop_id,dish_id,stock,stock_enabled,sold_out,updated_at) VALUES (?,?,?,?,?,NOW())",
                shopId, dishId, normalizedStock != null ? normalizedStock : -1, stockEnabled != null ? stockEnabled : 0,
                normalizedSoldOut != null ? normalizedSoldOut : 0);
        if (normalizedStock == null && Integer.valueOf(0).equals(normalizedSoldOut)) {
            jdbc.update("UPDATE t_dish_shop SET sold_out=CASE WHEN stock=0 THEN 1 ELSE 0 END,updated_at=NOW() "
                    + "WHERE shop_id=? AND dish_id=?", shopId, dishId);
        } else {
            jdbc.update("UPDATE t_dish_shop SET stock=COALESCE(?,stock),stock_enabled=COALESCE(?,stock_enabled),sold_out=COALESCE(?,sold_out),updated_at=NOW() "
                    + "WHERE shop_id=? AND dish_id=?", normalizedStock, stockEnabled, normalizedSoldOut, shopId, dishId);
        }
        Dish dish = dishService.getById(dishId);
        String dishName = dish != null ? dish.getName() : null;
        Boolean onsale = jdbc.queryForObject("SELECT COALESCE(ds.onsale_override,d.onsale) FROM t_dish_shop ds "
                        + "JOIN t_dish d ON d.id=ds.dish_id WHERE ds.shop_id=? AND ds.dish_id=?",
                Boolean.class, shopId, dishId);
        AfterCommitExecutor.execute("kds_authority_availability", () ->
                pushService.notifyCatalogChanged("kds_authority_" + operationType, dishId, dishName, onsale));
    }
}
