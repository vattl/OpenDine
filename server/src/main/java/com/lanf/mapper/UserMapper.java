package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.User;
import org.apache.ibatis.annotations.Param;

import java.math.BigDecimal;
import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 用户表 Mapper 接口
 * MyBatis-Plus 会自动生成基本CRUD方法
 */
public interface UserMapper extends BaseMapper<User> {

    // 如需扩展自定义SQL，可在此处添加方法声明
    // 例如：List<User> selectByPoints(Integer minPoints);

    /**
     * 根据openid查询用户信息
     * @param openid 微信用户唯一标识
     * @return 用户信息实体，如果没有找到则返回null
     */
    User selectByOpenid(String openid);

    User selectByInvite_code(String invite_code);

    List<User> getAllUsers();

    /** 查询近 7 天内注册的用户（t_user.time >= NOW()-7天） */
    List<User> selectSevenDaysUser();

    /** 查询上月注册的用户（按 t_user.time 所在年月等于上月） */
    List<User> selectLastMonthUser();

    /** 查询本月注册的用户（按 t_user.time 所在年月等于本月） */
    List<User> selectThisMonthUser();

    /** 查询指定时间段内注册的用户（t_user.time 在 [start_time, end_time] 闭区间） */
    List<User> selectScopeUser(@Param("start_time") Date start_time, @Param("end_time") Date end_time);

    List<Map<String, Object>> pageUserListWithStats(@Param("p") Map<String, Object> params);

    Long countUserListWithStats(@Param("p") Map<String, Object> params);

    /** D023：轻量分页（仅 t_user 基础字段，聚合字段置 null）；includeStats=true 时走 pageUserListWithStats */
    List<Map<String, Object>> pageUserListLight(@Param("p") Map<String, Object> params);

    Long countUserListLight(@Param("p") Map<String, Object> params);

    /** 增加本金（正数）：principal_balance 与 balance（总余额）同额增加 */
    int addBalance(@Param("userId") Integer userId, @Param("amount") BigDecimal amount);

    /** 增加赠送金（正数）：gift_balance 与 balance 同额增加 */
    int addGiftBalance(@Param("userId") Integer userId, @Param("amount") BigDecimal amount);

    /** 同时增加本金与赠送金；balance 增加 principal+gift */
    int addBalanceAndGift(@Param("userId") Integer userId,
                          @Param("principal") BigDecimal principal,
                          @Param("gift") BigDecimal gift);

    /**
     * 仅从本金扣减（正数 amount）；principal_balance 与 balance 同额减少。
     */
    int subtractBalanceIfEnough(@Param("userId") Integer userId, @Param("amount") BigDecimal amount);

    /** 仅从赠送金列扣减（正数 amount） */
    int subtractGiftBalanceIfEnough(@Param("userId") Integer userId, @Param("amount") BigDecimal amount);

    /**
     * 按已算好的本金/赠送金扣减额同时扣两列；各参数为正数，且两列当前值分别充足。
     */
    int subtractBalanceSplitIfEnough(@Param("userId") Integer userId,
                                   @Param("principal") BigDecimal principal,
                                   @Param("gift") BigDecimal gift);

    /**
     * 将 {@code balance} 校对为 {@code principal_balance + gift_balance}（两位小数），用于充值入账后纠偏。
     * @return 影响行数（正常为 1）
     */
    int reconcileUserBalanceTotal(@Param("userId") Integer userId);
}
