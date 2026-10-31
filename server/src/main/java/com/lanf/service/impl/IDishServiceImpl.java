package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Dish;
import com.lanf.mapper.DishMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.IDishService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 菜品Service实现类
 */
@Service("dishService")
public class IDishServiceImpl extends ServiceImpl<DishMapper,Dish> implements IDishService {

    @Autowired
    private DishMapper dishMapper;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private DishMenuPushService dishMenuPushService;

    @Override
    public List<Dish> list(Map<String, Object> map) {
        return dishMapper.list(map);
    }

    @Override
    public Long getTotal(Map<String, Object> map) {
        return dishMapper.getTotal(map);
    }

    @Override
    public List<Dish> listHqTemplate(Map<String, Object> map) {
        return dishMapper.listHqTemplate(map);
    }

    @Override
    public Long getTotalHqTemplate(Map<String, Object> map) {
        return dishMapper.getTotalHqTemplate(map);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> importFromHqToShop(Integer shopId, List<Integer> dishIds) {
        Map<String, Object> out = new HashMap<>();
        int imported = 0;
        int skipped = 0;
        List<Integer> invalidIds = new ArrayList<>();
        if (shopId == null || dishIds == null || dishIds.isEmpty()) {
            out.put("imported", 0);
            out.put("skipped", 0);
            out.put("invalidIds", invalidIds);
            return out;
        }
        Set<Integer> unique = new LinkedHashSet<>(dishIds);
        for (Integer dishId : unique) {
            if (dishId == null || dishId <= 0) {
                continue;
            }
            Dish dish = dishMapper.selectById(dishId);
            if (dish == null) {
                invalidIds.add(dishId);
                continue;
            }
            int n = dishShopMapper.insertIgnoreLink(shopId, dishId);
            if (n > 0) {
                imported++;
            } else {
                skipped++;
            }
        }
        if (imported > 0) {
            dishMenuPushService.notifyCatalogChanged("import_from_hq_batch", null, null, null);
        }
        out.put("imported", imported);
        out.put("skipped", skipped);
        out.put("invalidIds", invalidIds);
        return out;
    }
}
