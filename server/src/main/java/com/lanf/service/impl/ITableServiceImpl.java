package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Table;
import com.lanf.mapper.TableMapper;
import com.lanf.service.ITableService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;


/**
* 桌号Service实现类
*/
@Service("tableService")
public class ITableServiceImpl extends ServiceImpl<TableMapper,Table> implements ITableService {

   @Autowired
   private TableMapper tableMapper;


   @Override
   public List<Table> list(Map<String, Object> map) {
      return tableMapper.list(map);
   }

   @Override
   public Long getTotal(Map<String, Object> map) {
      return tableMapper.getTotal(map);
   }
}
