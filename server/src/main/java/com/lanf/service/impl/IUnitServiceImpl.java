package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Unit;
import com.lanf.mapper.UnitMapper;
import com.lanf.service.IUnitService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;


/**
 * 菜品单位Service实现类
 */
@Service("unitService")
public class IUnitServiceImpl extends ServiceImpl<UnitMapper,Unit> implements IUnitService {

    @Autowired
    private UnitMapper unitMapper;

}
