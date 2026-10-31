package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.CategoryShop;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;

public interface CategoryShopMapper extends BaseMapper<CategoryShop> {

    @Insert("INSERT INTO t_category_shop (shop_id, category_id, sorting_override) "
            + "VALUES (#{shopId}, #{categoryId}, #{sorting}) "
            + "ON DUPLICATE KEY UPDATE sorting_override=VALUES(sorting_override), updated_at=CURRENT_TIMESTAMP")
    int upsertSorting(@Param("shopId") Integer shopId,
                      @Param("categoryId") Integer categoryId,
                      @Param("sorting") Integer sorting);
}

