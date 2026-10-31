package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.Table;

import java.util.List;
import java.util.Map;


/**
 * 菜品Service接口
 */
public interface IDishService extends IService<Dish> {

    /**
     * 根据条件 分页查询
     * @param map
     * @return
     */
    public List<Dish> list(Map<String,Object> map);

    /**
     * 根据条件，查询总记录数
     * @param map
     * @return
     */
    public Long getTotal(Map<String,Object> map);

    /**
     * 总部标准菜分页（不按 t_dish_shop 过滤）
     */
    List<Dish> listHqTemplate(Map<String, Object> map);

    Long getTotalHqTemplate(Map<String, Object> map);

    /**
     * 将总部菜品挂到门店菜单（t_dish_shop 去重）；分类沿用 t_dish.typeId，不复制 t_dish 行。
     *
     * @return imported、skipped、invalidIds
     */
    Map<String, Object> importFromHqToShop(Integer shopId, List<Integer> dishIds);
}
