package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Table;

import java.util.List;
import java.util.Map;


/**
 * 桌号Mapper接口
 */
public interface TableMapper extends BaseMapper<Table> {

    /**
     * 根据条件 分页查询
     * @param map
     * @return
     */
    public List<Table> list(Map<String,Object> map);

    /**
     * 根据条件，查询订单总记录数
     * @param map
     * @return
     */
    public Long getTotal(Map<String,Object> map);

}
