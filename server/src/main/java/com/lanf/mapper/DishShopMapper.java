package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.DishShop;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

/**
 * 门店-菜品关联
 */
public interface DishShopMapper extends BaseMapper<DishShop> {

    /**
     * 幂等插入；已存在 (shop_id, dish_id) 时忽略（依赖 uk_shop_dish）
     */
    int insertIgnoreLink(@Param("shopId") Integer shopId, @Param("dishId") Integer dishId);

    @Update("UPDATE t_dish_shop SET sorting_override=#{sorting}, updated_at=CURRENT_TIMESTAMP "
            + "WHERE shop_id=#{shopId} AND dish_id=#{dishId}")
    int updateSortingOverride(@Param("shopId") Integer shopId,
                              @Param("dishId") Integer dishId,
                              @Param("sorting") Integer sorting);
}
