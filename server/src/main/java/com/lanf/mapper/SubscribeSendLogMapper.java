package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.SubscribeSendLog;
import org.apache.ibatis.annotations.Mapper;

/**
 * 微信订阅消息发送审计与调用日志 Mapper
 */
@Mapper
public interface SubscribeSendLogMapper extends BaseMapper<SubscribeSendLog> {
}
