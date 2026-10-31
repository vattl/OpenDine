package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Category;
import com.lanf.entity.Table;

import java.util.List;
import java.util.Map;


/**
 * 菜单类别Mapper接口
 */
public interface CategoryMapper extends BaseMapper<Category> {


    List<Table> list(Map<String, Object> map);

    Long getTotal(Map<String, Object> map);

    Category findById(Integer id);
}
