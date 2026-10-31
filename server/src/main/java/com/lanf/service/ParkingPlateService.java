package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.ParkingPlate;

/**
 * 车牌服务接口
 */
public interface ParkingPlateService extends IService<ParkingPlate> {
    /**
     * 根据用户ID和车牌号查询车牌信息
     */
    ParkingPlate getPlateByUserIdAndNumber(Long userId, String plateNumber);
}