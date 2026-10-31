package com.lanf.payment.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.payment.entity.WechatNativePaymentAttemptEntity;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface WechatNativePaymentAttemptMapper extends BaseMapper<WechatNativePaymentAttemptEntity> {
}
