package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Category;
import com.lanf.entity.Table;

import java.util.List;
import java.util.Map;


/**
 * 菜单分类Service接口
 */
public interface ICategoryService extends IService<Category> {

    /**
     * 根据条件 分页查询
     * @param map
     * @return
     */
    public List<Table> list(Map<String,Object> map);

    /**
     * 根据条件，查询总记录数
     * @param map
     * @return
     */
    public Long getTotal(Map<String,Object> map);


}
