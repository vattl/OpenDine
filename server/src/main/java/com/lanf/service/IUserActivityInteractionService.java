package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.UserActivityInteraction;

/**
 * 用户活动交互服务接口
 * 继承IService获得MyBatis-Plus提供的save、count等基础CRUD方法
 */
public interface IUserActivityInteractionService extends IService<UserActivityInteraction> {
    // 可以添加自定义业务方法
    boolean hasUserClosedToday(Integer is_enabled,Long userId, Long activityId);
}
    