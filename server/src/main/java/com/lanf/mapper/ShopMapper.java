package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Shop;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface ShopMapper extends BaseMapper<Shop> {

    /** 统一排序锁：同一门店的分类/菜品重排串行，不同门店互不阻塞。 */
    @Select("SELECT id FROM t_shop WHERE id=#{shopId} FOR UPDATE")
    Integer selectIdForUpdate(@Param("shopId") Integer shopId);
}
