package com.lanf.util;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.service.IDishService;
import org.springframework.util.StringUtils;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 备货预测/计划：仅纳入当前已上架菜品（与 C 端菜单一致，连锁门店取 {@code ifnull(onsale_override, onsale)}）。
 */
public final class StockPrepOnsaleCatalog {

    private StockPrepOnsaleCatalog() {}

    public static final class Index {
        private final Set<String> names;
        private final Map<String, Integer> nameToId;

        public Index(Set<String> names, Map<String, Integer> nameToId) {
            this.names = names == null ? Collections.emptySet() : names;
            this.nameToId = nameToId == null ? Collections.emptyMap() : nameToId;
        }

        public boolean containsName(String dishName) {
            if (!StringUtils.hasText(dishName)) {
                return false;
            }
            return names.contains(dishName.trim());
        }

        public Set<String> getNames() {
            return names;
        }

        public Map<String, Integer> getNameToId() {
            return nameToId;
        }

        public Integer resolveId(String dishName) {
            if (!StringUtils.hasText(dishName)) {
                return null;
            }
            return nameToId.get(dishName.trim());
        }
    }

    public static Index load(IDishService dishService, Integer shopId) {
        if (dishService == null) {
            return new Index(Collections.emptySet(), Collections.emptyMap());
        }
        List<Dish> dishes;
        if (shopId != null) {
            Map<String, Object> params = new HashMap<>(2);
            params.put("shop_id", shopId);
            dishes = dishService.list(params);
        } else {
            QueryWrapper<Dish> q = new QueryWrapper<Dish>().select("id", "name");
            DishCustomerMenuFilters.applyTo(q);
            dishes = dishService.list(q);
        }
        Set<String> names = new HashSet<>();
        Map<String, Integer> nameToId = new HashMap<>();
        if (dishes != null) {
            for (Dish d : dishes) {
                if (d == null || !StringUtils.hasText(d.getName())) {
                    continue;
                }
                if (shopId != null && !d.isOnsale()) {
                    continue;
                }
                String key = d.getName().trim();
                names.add(key);
                nameToId.putIfAbsent(key, d.getId());
            }
        }
        return new Index(names, nameToId);
    }
}
