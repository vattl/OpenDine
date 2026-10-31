package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDishScreen;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.entity.KdsStationCategory;
import com.lanf.kds.mapper.KdsDishScreenMapper;
import com.lanf.kds.mapper.KdsStationCategoryMapper;
import com.lanf.service.IDishService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

/**
 * 菜品 → screen_tag → station（烤制屏）；抓串/总出餐屏不生成 ticket。
 */
@Service
public class KdsRoutingService {

    @Autowired
    private KdsDishScreenMapper dishScreenMapper;
    @Autowired
    private KdsStationCategoryMapper stationCategoryMapper;
    @Autowired
    private KdsStationService stationService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private IDishService dishService;

    public static final class RouteTarget {
        public final String screenTag;
        public final Long stationId;

        RouteTarget(String screenTag, Long stationId) {
            this.screenTag = screenTag;
            this.stationId = stationId;
        }

        public boolean createsTicket() {
            return stationId != null && !KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag)
                    && !KdsScreenTag.EXPEDITION.equals(screenTag);
        }
    }

    public RouteTarget resolve(int shopId, OrderDetail detail) {
        if (detail == null) {
            return null;
        }
        if ("combo_header".equalsIgnoreCase(trim(detail.getLine_type()))) {
            return null;
        }
        String screenTag = resolveScreenTag(shopId, detail);
        if (!KdsScreenTag.isValid(screenTag)) {
            return null;
        }
        if (KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag) || KdsScreenTag.EXPEDITION.equals(screenTag)) {
            return new RouteTarget(screenTag, null);
        }
        KdsStation station = stationService.findByScreenTag(shopId, screenTag);
        if (station == null || station.getEnabled() == null || station.getEnabled() != 1) {
            return null;
        }
        return new RouteTarget(screenTag, station.getId());
    }

    private String resolveScreenTag(int shopId, OrderDetail detail) {
        Integer dishId = resolveDishId(detail);
        if (dishId != null) {
            KdsDishScreen ds = dishScreenMapper.selectOne(new QueryWrapper<KdsDishScreen>()
                    .eq("shop_id", shopId)
                    .eq("dish_id", dishId)
                    .last("LIMIT 1"));
            if (ds != null && KdsScreenTag.isValid(ds.getScreen_tag())) {
                return ds.getScreen_tag();
            }
        }
        if (StringUtils.hasText(detail.getCid())) {
            KdsStationCategory sc = stationCategoryMapper.selectOne(new QueryWrapper<KdsStationCategory>()
                    .eq("cid", detail.getCid().trim())
                    .last("LIMIT 1"));
            if (sc != null) {
                KdsStation station = stationService.getById(sc.getStation_id());
                if (station != null && shopIdEquals(station.getShop_id(), shopId)) {
                    return station.getScreen_tag();
                }
            }
        }
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        return cfg.getDefault_screen_tag();
    }

    private Integer resolveDishId(OrderDetail detail) {
        if (detail.getDish_id() != null && detail.getDish_id() > 0) {
            return detail.getDish_id();
        }
        if (!StringUtils.hasText(detail.getName())) {
            return null;
        }
        Dish dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                .eq(Dish::getName, detail.getName().trim())
                .last("LIMIT 1"));
        return dish != null ? dish.getId() : null;
    }

    private static String trim(String s) {
        return s == null ? null : s.trim();
    }

    private static boolean shopIdEquals(Integer a, int b) {
        return a != null && a == b;
    }
}
