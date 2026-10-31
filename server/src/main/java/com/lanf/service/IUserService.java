package com.lanf.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.dto.R;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.Coupon;
import com.lanf.entity.User;
import com.lanf.entity.UserCoupon;

import java.math.BigDecimal;
import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 用户服务接口
 */
public interface IUserService extends IService<User> {


    String DEFAULT_NICKNAME_PREFIX = "老肥吃货";

    /**
     * 生成统一默认昵称（老肥吃货 + id号）
     * @param id 用户ID
     * @return 默认昵称
     */
    String buildDefaultNickname(Integer id);

    User selectByInvite_code(String invite_code);
    /**
     * 根据openid查询用户
     * @param openid 用户唯一标识
     * @return 用户信息
     */
    User getUserByOpenid(String openid);

    /**
     * 根据手机号手机号查询用户
     * @param phone 手机号
     * @return 用户信息
     */
    User getUserByPhone(String phone);

    /** Bind a phone to an openid, preserving an existing phone owner's profile. */
    User bindPhoneToOpenid(String openid, String phone, String sessionKey);

    /**
     * 增加用户积分
     * @param userId 用户ID
     * @param points 要增加的积分
     * @return 是否操作成功
     */
    boolean addPoints(Integer userId, Integer points);

    /**
     * 更新用户会话密钥
     * @param openid 用户唯一标识
     * @param sessionKey 新的会话密钥
     * @return 是否操作成功
     */
    boolean updateSessionKey(String openid, String sessionKey);



    /**
     * 查询积分大于等于指定值的用户
     * @param minPoints 最小积分值
     * @return 用户列表
     */
    List<User> getUsersWithPointsGreaterThanEqual(Integer minPoints);

    /**
     * 获取全部用户列表（未分页，慎用数据量大时）
     * @return 所有用户信息列表
     */
    List<User> getAllUsers();

    /**
     * 查询近 7 天内注册的用户（按 t_user.time）
     */
    List<User> getSevenDaysUser();
    List<User> getSevenDaysUser(Integer shopId);

    /**
     * 查询上月注册的用户（按 t_user.time 所在年月）
     */
    List<User> getLastMonthUser();
    List<User> getLastMonthUser(Integer shopId);

    /**
     * 查询本月注册的用户（按 t_user.time 所在年月）
     */
    List<User> getThisMonthUser();
    List<User> getThisMonthUser(Integer shopId);

    /**
     * 查询指定时间段内注册的用户（t_user.time 在 [startTime, endTime] 闭区间）
     * @param startTime 开始时间
     * @param endTime 结束时间
     */
    List<User> getScopeUser(Date startTime, Date endTime);
    List<User> getScopeUser(Date startTime, Date endTime, Integer shopId);

    /**
     * 分页查询用户列表，避免一次性加载过多
     * @param pageNum 页码，从 1 开始
     * @param pageSize 每页条数
     * @param query 可选，按 name/phone/openid 模糊查询
     * @return 分页结果（含 records 与 total）
     */
    IPage<User> pageUserList(int pageNum, int pageSize, String query);
    IPage<User> pageUserList(int pageNum, int pageSize, String query, Integer shopId);

    Map<String, Object> pageUserListWithStats(Map<String, Object> params);

    /** @param couponId 用户券记录 t_user_coupon.id；@param openid 用户 openid */
    UserCouponDTO selectByCouponById(Long couponId, String openid);

    /**
     * 增加用户本金（元）；{@code t_user.principal_balance} 与 {@code t_user.balance}（总余额）同额增加。
     */
    boolean addBalance(Integer userId, BigDecimal amountYuan);

    /**
     * 增加用户赠送金（元）；{@code gift_balance} 与 {@code balance}（总余额）同额增加。
     */
    boolean addGiftBalance(Integer userId, BigDecimal amountYuan);

    /**
     * 同时增加本金与赠送金；{@code balance} 增加 principal+gift（总余额恒等于二者之和）。
     */
    boolean addBalanceAndGift(Integer userId, BigDecimal principalYuan, BigDecimal giftYuan);

    /**
     * 仅从本金扣减；{@code principal_balance} 与 {@code balance} 同额减少；本金不足时返回 false。
     */
    boolean subtractBalanceIfEnough(Integer userId, BigDecimal amountYuan);

    /**
     * 仅从赠送金扣减。
     */
    boolean subtractGiftBalanceIfEnough(Integer userId, BigDecimal amountYuan);

    /**
     * 按指定本金/赠送金数额同时扣减两列（须已按业务规则拆好分）。
     */
    boolean subtractBalanceSplitIfEnough(Integer userId, BigDecimal principalYuan, BigDecimal giftYuan);

    /**
     * 从总余额钱包按「当前本金/赠送金」占比以分整数拆分后扣减；{@code balance} 为总余额须充足。
     */
    boolean subtractWalletProportionalIfEnough(Integer userId, BigDecimal totalYuan);

}
