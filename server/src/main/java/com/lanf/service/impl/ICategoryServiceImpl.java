package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Category;
import com.lanf.entity.Table;
import com.lanf.mapper.CategoryMapper;
import com.lanf.service.ICategoryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;


/**
 * 菜单分类Service实现类
 */
@Service("categoryService")
public class ICategoryServiceImpl extends ServiceImpl<CategoryMapper, Category> implements ICategoryService {

    @Autowired
    private CategoryMapper categoryMapper;


    @Override
    public List<Table> list(Map<String, Object> map) {
        return categoryMapper.list(map);
    }

    @Override
    public Long getTotal(Map<String, Object> map) {
        return categoryMapper.getTotal(map);
    }
}
