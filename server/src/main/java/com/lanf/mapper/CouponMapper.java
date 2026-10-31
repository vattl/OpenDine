package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Coupon;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;
import java.util.List;

@Mapper
public interface CouponMapper extends BaseMapper<Coupon> {
    // 查询可用优惠券（未过期、已启用、库存充足）
    List<Coupon> selectAvailableCoupons();

    // 根据ID查询有效优惠券
    Coupon selectValidCouponById(@Param("id") Long id);

    /** 发放成功一张用户券时递增（与 t_user_coupon 写入一致） */
    @Update("UPDATE t_coupon SET granted_count = IFNULL(granted_count, 0) + 1 WHERE id = #{couponId}")
    int incrementGrantedCount(@Param("couponId") Long couponId);
}