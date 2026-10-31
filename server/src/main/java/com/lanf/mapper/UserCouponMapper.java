package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.Coupon;
import com.lanf.entity.UserCoupon;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

import java.util.Date;
import java.util.List;

@Mapper
public interface UserCouponMapper extends BaseMapper<UserCoupon> {
    /**
     * 用户券列表（联合 t_coupon）。{@code status=0} 时按 {@code now} 过滤：用户券未过期、模板未结束、模板行存在；不过滤未到模板 {@code start_time}。
     */
    List<UserCouponDTO> getUserCoupon(@Param("user_openid") String user_openid, @Param("now") Date now, @Param("status") Integer status);

    /**
     * 当前用户下、指定券模板(t_coupon.id)且未使用的一条用户券（多领时取最近领取的）。
     */
    UserCouponDTO selectValidCouponById(@Param("couponId") Long couponId, @Param("user_openid") String user_openid);

    /** 用户券主键 + openid，联合模板（任意状态的用户券，用于详情）。 */
    UserCouponDTO selectUserCouponJoinById(@Param("id") Long id, @Param("user_openid") String user_openid);

    long countUserCouponForPage(@Param("user_openid") String user_openid, @Param("now") Date now, @Param("status") Integer status);

    List<UserCouponDTO> getUserCouponPage(@Param("user_openid") String user_openid, @Param("now") Date now, @Param("status") Integer status,
                                          @Param("offset") int offset, @Param("limit") int limit);

    long adminCountUserCoupons(@Param("couponIds") List<Long> couponIds,
                               @Param("couponId") Long couponId,
                               @Param("userOpenid") String userOpenid,
                               @Param("status") Integer status,
                               @Param("orderNoLike") String orderNoLike,
                               @Param("getTimeStart") Date getTimeStart,
                               @Param("getTimeEnd") Date getTimeEnd);

    List<UserCouponDTO> adminUserCouponPage(@Param("couponIds") List<Long> couponIds,
                                            @Param("couponId") Long couponId,
                                            @Param("userOpenid") String userOpenid,
                                            @Param("status") Integer status,
                                            @Param("orderNoLike") String orderNoLike,
                                            @Param("getTimeStart") Date getTimeStart,
                                            @Param("getTimeEnd") Date getTimeEnd,
                                            @Param("offset") int offset,
                                            @Param("limit") int limit);
}