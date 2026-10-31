package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/** 批量解析订单明细对应菜品的 KDS 超时阈值，避免看板逐行查询菜品。 */
@Service
public class KdsDishServingDurationService {

    public static final int DEFAULT_MINUTES = 10;

    @Autowired
    private IDishService dishService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private DishShopMapper dishShopMapper;

    public Map<Integer, Integer> resolveSecondsByDetailIds(Collection<Integer> detailIds, int fallbackSeconds) {
        return resolveSecondsByDetailIds(detailIds, fallbackSeconds, null);
    }

    public Map<Integer, Integer> resolveSecondsByDetailIds(Collection<Integer> detailIds, int fallbackSeconds, Integer shopId) {
        if (detailIds == null || detailIds.isEmpty()) {
            return Collections.emptyMap();
        }
        Set<Integer> ids = detailIds.stream().filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        if (ids.isEmpty()) {
            return Collections.emptyMap();
        }
        List<OrderDetail> details = orderDetailService.listByIds(ids);
        return resolveSecondsByDetails(details, fallbackSeconds, shopId);
    }

    public Map<Integer, Integer> resolveSecondsByDetails(Collection<OrderDetail> details, int fallbackSeconds) {
        return resolveSecondsByDetails(details, fallbackSeconds, null);
    }

    public Map<Integer, Integer> resolveSecondsByDetails(Collection<OrderDetail> details, int fallbackSeconds, Integer shopId) {
        if (details == null || details.isEmpty()) {
            return Collections.emptyMap();
        }
        int fallback = normalizeFallback(fallbackSeconds);
        Set<Integer> dishIds = details.stream()
                .filter(Objects::nonNull)
                .map(OrderDetail::getDish_id)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        Map<Integer, Dish> dishMap = new HashMap<>();
        if (!dishIds.isEmpty()) {
            List<Dish> dishes = dishService.listByIds(dishIds);
            if (dishes != null) {
                dishMap = dishes.stream()
                        .filter(d -> d != null && d.getId() != null)
                        .collect(Collectors.toMap(Dish::getId, Function.identity(), (a, b) -> a));
            }
        }
        // 门店出餐时长覆盖：serving_duration_override 优先于总部（方案 A）；无 shopId（旧调用）不查门店
        if (shopId != null && !dishIds.isEmpty()) {
            List<DishShop> links = dishShopMapper.selectList(new QueryWrapper<DishShop>()
                    .eq("shop_id", shopId)
                    .in("dish_id", dishIds));
            if (links != null) {
                for (DishShop l : links) {
                    if (l.getDish_id() != null && l.getServing_duration_override() != null) {
                        Dish d = dishMap.get(l.getDish_id());
                        if (d != null) {
                            d.setServing_duration_minutes(l.getServing_duration_override());
                        }
                    }
                }
            }
        }
        Map<Integer, Integer> result = new HashMap<>();
        for (OrderDetail detail : details) {
            if (detail == null || detail.getId() == null) {
                continue;
            }
            Dish dish = detail.getDish_id() != null ? dishMap.get(detail.getDish_id()) : null;
            result.put(detail.getId(), secondsForDish(dish, fallback));
        }
        return result;
    }

    public static int secondsForDetail(Integer detailId, Map<Integer, Integer> secondsByDetail,
                                       int fallbackSeconds) {
        int fallback = normalizeFallback(fallbackSeconds);
        if (detailId == null || secondsByDetail == null) {
            return fallback;
        }
        return secondsByDetail.getOrDefault(detailId, fallback);
    }

    static int secondsForDish(Dish dish, int fallbackSeconds) {
        Integer minutes = dish != null ? dish.getServing_duration_minutes() : null;
        if (minutes == null || minutes <= 0) {
            return normalizeFallback(fallbackSeconds);
        }
        return minutes > Integer.MAX_VALUE / 60 ? Integer.MAX_VALUE : minutes * 60;
    }

    private static int normalizeFallback(int fallbackSeconds) {
        return fallbackSeconds > 0 ? fallbackSeconds : DEFAULT_MINUTES * 60;
    }
}
