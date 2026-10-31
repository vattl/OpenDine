package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.UserActivityInteraction;
import com.lanf.mapper.UserActivityInteractionMapper;
import com.lanf.service.IUserActivityInteractionService;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.Date;

/**
 * 用户活动交互服务实现类
 */
@Service
public class UserActivityInteractionServiceImpl
        extends ServiceImpl<UserActivityInteractionMapper, UserActivityInteraction>
        implements IUserActivityInteractionService {

    @Override
    public boolean hasUserClosedToday(Integer is_enabled,Long userId, Long activityId) {
        // 示例：查询用户今日是否关闭过该活动
        int count = count(new QueryWrapper<UserActivityInteraction>()
                .eq("user_id", userId)
                .eq("activity_id", activityId)
                .eq("interaction_type", "close")
                .eq("date", LocalDate.now()));

        return count > 0;
    }

    // 使用继承的save方法示例
    public void recordInteraction(Long userId, Long activityId, String type) {
        UserActivityInteraction interaction = new UserActivityInteraction();
        interaction.setUserId(userId);
        interaction.setActivityId(activityId);
        interaction.setInteractionType(type);
        interaction.setInteractionTime(new Date());
        interaction.setDate(LocalDate.now()); // 或LocalDate.now()

        // 调用从IService继承的save方法
        save(interaction);
    }
}
    