package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Dish;
import com.lanf.entity.Table;

import java.util.List;
import java.util.Map;

/**
 * 菜品Mapper接口
 */
public interface DishMapper extends BaseMapper<Dish> {


    List<Dish> list(Map<String, Object> map);

    Long getTotal(Map<String, Object> map);

    List<Dish> listHqTemplate(Map<String, Object> map);

    Long getTotalHqTemplate(Map<String, Object> map);
}
