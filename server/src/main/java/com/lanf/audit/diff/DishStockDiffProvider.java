package com.lanf.audit.diff;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IOrderDetailService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 退菜/库存回退类操作的前后状态快照：订单明细行关联菜品的门店可售库存（t_dish_shop.stock）。
 * targetId 为订单明细 id（detailId）。查库失败返回 null（不阻断审计记录）。
 */
@Component
public class DishStockDiffProvider implements DiffProvider {

    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private DishShopMapper dishShopMapper;

    @Override
    public Map<String, Object> captureBefore(String targetId) {
        return capture(targetId);
    }

    @Override
    public Map<String, Object> captureAfter(String targetId) {
        return capture(targetId);
    }

    private Map<String, Object> capture(String detailId) {
        Integer id = parseInt(detailId);
        if (id == null) {
            return null;
        }
        try {
            OrderDetail detail = orderDetailService.getById(id);
            if (detail == null || detail.getDish_id() == null) {
                return null;
            }
            DishShop shop = dishShopMapper.selectOne(
                    new QueryWrapper<DishShop>().eq("dish_id", detail.getDish_id()).last("LIMIT 1"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("detailId", id);
            m.put("dishId", detail.getDish_id());
            m.put("quantity", detail.getQuantity());
            m.put("stock", shop != null ? shop.getStock() : null);
            m.put("stockEnabled", shop != null ? shop.getStock_enabled() : null);
            return m;
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer parseInt(String s) {
        if (s == null || s.trim().isEmpty()) {
            return null;
        }
        try {
            return Integer.valueOf(s.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
