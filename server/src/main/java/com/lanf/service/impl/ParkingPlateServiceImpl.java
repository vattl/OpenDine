package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.ParkingPlate;
import com.lanf.mapper.ParkingPlateMapper;
import com.lanf.service.ParkingPlateService;
import org.springframework.stereotype.Service;

/**
 * 车牌服务实现
 */
@Service
public class ParkingPlateServiceImpl extends ServiceImpl<ParkingPlateMapper, ParkingPlate> implements ParkingPlateService {

    @Override
    public ParkingPlate getPlateByUserIdAndNumber(Long userId, String plateNumber) {
        LambdaQueryWrapper<ParkingPlate> queryWrapper = new LambdaQueryWrapper<>();
        queryWrapper.eq(ParkingPlate::getUser_id, userId)
                .eq(ParkingPlate::getPlate_number, plateNumber)
                .eq(ParkingPlate::getIs_default, 0);
        return baseMapper.selectOne(queryWrapper);
    }
}