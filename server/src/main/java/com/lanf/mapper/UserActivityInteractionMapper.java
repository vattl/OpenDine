package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.UserActivityInteraction;
import org.apache.ibatis.annotations.Mapper;

/**
 * 用户活动交互数据访问接口
 */
@Mapper
public interface UserActivityInteractionMapper extends BaseMapper<UserActivityInteraction> {
}
