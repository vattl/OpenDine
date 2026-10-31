package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.dto.R;
import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.Coupon;
import com.lanf.entity.User;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.InviteService;
import com.lanf.mapper.UserMapper;
import com.lanf.service.IUserService;
import com.lanf.util.UserWalletSplitUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * 用户服务实现类
 */
@Service
public class IUserServiceImpl extends ServiceImpl<UserMapper, User> implements IUserService {
    private static final Logger log = LoggerFactory.getLogger(IUserServiceImpl.class);

    @Autowired
    private UserMapper UserMapper;

    @Autowired
    private UserCouponMapper UserCouponMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;


    @Override
    public String buildDefaultNickname(Integer id) {
        return DEFAULT_NICKNAME_PREFIX + (id != null ? id : "");
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean save(User entity) {
        if (entity == null) {
            return false;
        }
        ensureUserDefaults(entity);
        boolean success = super.save(entity);
        if (success && entity.getId() != null) {
            // 只有注册的时候首次填入默认昵称：老肥吃货 + id
            if (!StringUtils.hasText(entity.getName())) {
                String defaultNickname = buildDefaultNickname(entity.getId());
                entity.setName(defaultNickname);
                baseMapper.updateById(entity);
            }
        }
        return success;
    }

    @Override
    public User  selectByInvite_code(String invite_code) {
        return UserMapper.selectByInvite_code(invite_code);
    }

    @Override
    public UserCouponDTO selectByCouponById(Long couponId, String openid) {
        return UserCouponMapper.selectValidCouponById(couponId, openid);
    }



    @Override
    public User getUserByOpenid(String openid) {
        if (openid == null || openid.trim().isEmpty()) {
            return null;
        }
        String oid = openid.trim();
        User u = baseMapper.selectByOpenid(oid);
        if (u != null && walletBalanceDrifted(u)) {
            log.info("检测到用户钱包 balance 与本金+赠送不一致，自动纠偏: userId={} openid={}", u.getId(), oid);
            reconcileUserBalanceTotal(u.getId());
            u = reloadUserById(u.getId());
        }
        return u;
    }



    @Override
    public User getUserByPhone(String phone) {
        if (phone == null) {
            return null;
        }
        String normalized = normalizePhoneForLookup(phone);
        if (normalized == null || normalized.isEmpty()) {
            return null;
        }
        QueryWrapper<User> queryWrapper = new QueryWrapper<>();
        queryWrapper.eq("phone", normalized);
        queryWrapper.last("LIMIT 1");
        User u = baseMapper.selectOne(queryWrapper);
        if (u != null && walletBalanceDrifted(u)) {
            log.info("检测到用户钱包 balance 与本金+赠送不一致，自动纠偏: userId={} phone={}", u.getId(), normalized);
            reconcileUserBalanceTotal(u.getId());
            u = reloadUserById(u.getId());
        }
        if (u != null) {
            return u;
        }
        // 兼容库内存有空格、+86 等格式
        queryWrapper = new QueryWrapper<>();
        queryWrapper.apply("REPLACE(REPLACE(REPLACE(TRIM(phone), ' ', ''), '+86', ''), '-', '') = {0}", normalized);
        queryWrapper.last("LIMIT 1");
        u = baseMapper.selectOne(queryWrapper);
        if (u != null && walletBalanceDrifted(u)) {
            reconcileUserBalanceTotal(u.getId());
            u = reloadUserById(u.getId());
        }
        return u;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public User bindPhoneToOpenid(String openid, String phone, String sessionKey) {
        if (!StringUtils.hasText(openid)) throw new IllegalArgumentException("openid不能为空");
        if (!StringUtils.hasText(phone)) throw new IllegalArgumentException("手机号不能为空");
        String oid = openid.trim();
        String normalizedPhone = normalizePhoneForLookup(phone);
        User phoneOwner = getUserByPhone(normalizedPhone);
        User current = selectOneByOpenidRaw(oid);
        String effectiveSessionKey = StringUtils.hasText(sessionKey)
                ? sessionKey.trim() : (current != null ? current.getSession_key() : null);

        if (phoneOwner == null) {
            User target = current != null ? current : new User();
            target.setOpenid(oid);
            target.setPhone(normalizedPhone);
            if (StringUtils.hasText(effectiveSessionKey)) target.setSession_key(effectiveSessionKey);
            ensureUserDefaults(target);
            if (target.getId() == null) save(target); else baseMapper.updateById(target);
            return baseMapper.selectById(target.getId());
        }

        if (current != null && Objects.equals(phoneOwner.getId(), current.getId())) {
            phoneOwner.setPhone(normalizedPhone);
            if (StringUtils.hasText(effectiveSessionKey)) phoneOwner.setSession_key(effectiveSessionKey);
            baseMapper.updateById(phoneOwner);
            return baseMapper.selectById(phoneOwner.getId());
        }

        boolean foreignKeysDisabled = false;
        try {
            jdbcTemplate.execute("SET FOREIGN_KEY_CHECKS=0");
            foreignKeysDisabled = true;
            String oldOpenid = phoneOwner.getOpenid();
            if (StringUtils.hasText(oldOpenid) && !oldOpenid.trim().equals(oid)) {
                migrateOpenidReferences(oldOpenid.trim(), oid);
            }
            phoneOwner.setOpenid(oid);
            phoneOwner.setPhone(normalizedPhone);
            if (StringUtils.hasText(effectiveSessionKey)) phoneOwner.setSession_key(effectiveSessionKey);
            ensureUserDefaults(phoneOwner);
            if (current != null) baseMapper.deleteById(current.getId());
            baseMapper.updateById(phoneOwner);
        } finally {
            if (foreignKeysDisabled) jdbcTemplate.execute("SET FOREIGN_KEY_CHECKS=1");
        }
        return baseMapper.selectById(phoneOwner.getId());
    }

    private User selectOneByOpenidRaw(String openid) {
        return baseMapper.selectOne(new QueryWrapper<User>()
                .eq("openid", openid).last("LIMIT 1"));
    }

    private void ensureUserDefaults(User user) {
        if (user.getTime() == null) user.setTime(new Date());
        if (user.getUser_type() == null) user.setUser_type(0);
    }

    private void migrateOpenidReferences(String oldOpenid, String newOpenid) {
        updateOpenidReference("t_order", "openid", oldOpenid, newOpenid);
        updateOpenidReference("t_order", "pay_openid", oldOpenid, newOpenid);
        updateOpenidReference("t_user_coupon", "user_openid", oldOpenid, newOpenid);
        updateOpenidReference("t_user_address", "openid", oldOpenid, newOpenid);
        updateOpenidReference("t_member_recharge", "openid", oldOpenid, newOpenid);
        updateOpenidReference("t_queue_ticket", "openid", oldOpenid, newOpenid);
        updateOpenidReference("t_invite_record", "inviter_openid", oldOpenid, newOpenid);
        updateOpenidReference("t_invite_record", "invitee_openid", oldOpenid, newOpenid);
        updateOpenidReference("t_coupon_redeem_code", "used_openid", oldOpenid, newOpenid);
        jdbcTemplate.update("DELETE FROM t_user_last_shop WHERE openid = ?", newOpenid);
        updateOpenidReference("t_user_last_shop", "openid", oldOpenid, newOpenid);
    }

    private void updateOpenidReference(String table, String column, String oldOpenid, String newOpenid) {
        jdbcTemplate.update("UPDATE " + table + " SET " + column + " = ? WHERE " + column + " = ?",
                newOpenid, oldOpenid);
    }

    private static String normalizePhoneForLookup(String phone) {
        String p = phone.trim().replaceAll("\\s+", "");
        if (p.startsWith("+86")) {
            p = p.substring(3);
        } else if (p.length() == 13 && p.startsWith("86")) {
            p = p.substring(2);
        }
        p = p.replace("-", "");
        return p.isEmpty() ? null : p;
    }

    @Override
    public boolean addPoints(Integer userId, Integer points) {
        if (userId == null || points == null || points <= 0) {
            return false;
        }

        User user = baseMapper.selectById(userId);
        if (user == null) {
            return false;
        }
        int current = user.getPoints() != null ? user.getPoints() : 0;
        user.setPoints(current + points);
        return baseMapper.updateById(user) > 0;
    }

    @Override
    public boolean updateSessionKey(String openid, String sessionKey) {
        User user = getUserByOpenid(openid);
        if (user == null) {
            return false;
        }

        user.setSession_key(sessionKey);
        return baseMapper.updateById(user) > 0;
    }

    @Override
    public List<User> getUsersWithPointsGreaterThanEqual(Integer minPoints) {
        QueryWrapper<User> queryWrapper = new QueryWrapper<>();
        queryWrapper.ge("points", minPoints);
        queryWrapper.orderByDesc("points");
        return baseMapper.selectList(queryWrapper);
    }
    /**
     * 查询所有用户（未分页）
     * @return 所有用户的列表
     */
    @Override
    public List<User> getAllUsers() {
        return baseMapper.selectList(new QueryWrapper<User>().isNotNull("phone").ne("TRIM(phone)", ""));
    }

    @Override
    public List<User> getSevenDaysUser() {
        return getSevenDaysUser(null);
    }

    @Override
    public List<User> getSevenDaysUser(Integer shopId) {
        if (shopId == null || shopId <= 0) {
            return baseMapper.selectSevenDaysUser();
        }
        QueryWrapper<User> w = new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .apply("time >= DATE_SUB(NOW(), INTERVAL 7 DAY) AND time <= NOW()");
        applyShopMemberFilter(w, shopId);
        w.orderByDesc("time");
        return baseMapper.selectList(w);
    }

    @Override
    public List<User> getLastMonthUser() {
        return getLastMonthUser(null);
    }

    @Override
    public List<User> getLastMonthUser(Integer shopId) {
        if (shopId == null || shopId <= 0) {
            return baseMapper.selectLastMonthUser();
        }
        QueryWrapper<User> w = new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .apply("DATE_FORMAT(time, '%Y-%m') = DATE_FORMAT(DATE_SUB(NOW(), INTERVAL 1 MONTH), '%Y-%m')");
        applyShopMemberFilter(w, shopId);
        w.orderByDesc("time");
        return baseMapper.selectList(w);
    }

    @Override
    public List<User> getThisMonthUser() {
        return getThisMonthUser(null);
    }

    @Override
    public List<User> getThisMonthUser(Integer shopId) {
        if (shopId == null || shopId <= 0) {
            return baseMapper.selectThisMonthUser();
        }
        QueryWrapper<User> w = new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .apply("DATE_FORMAT(time, '%Y-%m') = DATE_FORMAT(NOW(), '%Y-%m')");
        applyShopMemberFilter(w, shopId);
        w.orderByDesc("time");
        return baseMapper.selectList(w);
    }

    @Override
    public List<User> getScopeUser(Date startTime, Date endTime) {
        return getScopeUser(startTime, endTime, null);
    }

    @Override
    public List<User> getScopeUser(Date startTime, Date endTime, Integer shopId) {
        if (startTime == null || endTime == null) {
            return Collections.emptyList();
        }
        if (shopId == null || shopId <= 0) {
            return baseMapper.selectScopeUser(startTime, endTime);
        }
        QueryWrapper<User> w = new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .between("time", startTime, endTime);
        applyShopMemberFilter(w, shopId);
        w.orderByDesc("time");
        return baseMapper.selectList(w);
    }

    @Override
    public IPage<User> pageUserList(int pageNum, int pageSize, String query) {
        return pageUserList(pageNum, pageSize, query, null);
    }

    @Override
    public IPage<User> pageUserList(int pageNum, int pageSize, String query, Integer shopId) {
        Page<User> page = new Page<>(pageNum, pageSize);
        QueryWrapper<User> wrapper = new QueryWrapper<>();
        wrapper.isNotNull("phone").ne("TRIM(phone)", "");
        if (query != null && !query.trim().isEmpty()) {
            String q = query.trim();
            wrapper.and(w -> w.like("name", q).or().like("phone", q).or().like("openid", q));
        }
        applyShopMemberFilter(wrapper, shopId);
        wrapper.orderByDesc("id");
        return baseMapper.selectPage(page, wrapper);
    }

    private void applyShopMemberFilter(QueryWrapper<User> wrapper, Integer shopId) {
        if (shopId != null && shopId > 0) {
            String shopOrderCond = (shopId == 1) ? "(shop_id = 1 OR shop_id IS NULL)" : "shop_id = " + shopId;
            String shopRechargeCond = (shopId == 1) ? "(shop_id = 1 OR shop_id IS NULL)" : "shop_id = " + shopId;
            String shopWalletCond = "shop_id = " + shopId;
            wrapper.and(w -> w
                    .inSql("openid", "SELECT openid FROM t_order WHERE " + shopOrderCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                    .or().inSql("openid", "SELECT pay_openid FROM t_order WHERE " + shopOrderCond + " AND pay_openid IS NOT NULL AND TRIM(pay_openid) <> ''")
                    .or().inSql("id", "SELECT user_id FROM t_member_recharge WHERE " + shopRechargeCond + " AND user_id IS NOT NULL")
                    .or().inSql("openid", "SELECT openid FROM t_member_recharge WHERE " + shopRechargeCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                    .or().inSql("id", "SELECT user_id FROM t_shop_member_wallet WHERE " + shopWalletCond + " AND user_id IS NOT NULL")
            );
        }
    }

    @Override
    public Map<String, Object> pageUserListWithStats(Map<String, Object> params) {
        Map<String, Object> result = new HashMap<>();
        // D023：默认轻量（仅 t_user 基础字段+分页）；includeStats=true 时走全量聚合
        boolean includeStats = Boolean.TRUE.equals(params.get("includeStats"));
        List<Map<String, Object>> records = includeStats
                ? baseMapper.pageUserListWithStats(params)
                : baseMapper.pageUserListLight(params);
        Long total = includeStats
                ? baseMapper.countUserListWithStats(params)
                : baseMapper.countUserListLight(params);
        result.put("records", records);
        result.put("total", total != null ? total : 0L);
        return result;
    }

    /** 将 balance 重写为 principal_balance + gift_balance（入账/扣款后及纠偏用） */
    private void reconcileUserBalanceTotal(Integer userId) {
        if (userId == null) {
            return;
        }
        int n = baseMapper.reconcileUserBalanceTotal(userId);
        if (n != 1) {
            log.warn("reconcileUserBalanceTotal: expected 1 row updated, userId={} affected={}", userId, n);
        }
    }

    private static BigDecimal nz(BigDecimal v) {
        return v != null ? v : BigDecimal.ZERO;
    }

    /** balance 与 principal+gift 偏差超过 2 分视为脏数据（历史脚本/旧逻辑导致） */
    private static boolean walletBalanceDrifted(User u) {
        if (u == null || u.getId() == null) {
            return false;
        }
        BigDecimal sum = nz(u.getPrincipal_balance()).add(nz(u.getGift_balance())).setScale(2, RoundingMode.HALF_UP);
        BigDecimal b = nz(u.getBalance()).setScale(2, RoundingMode.HALF_UP);
        return b.subtract(sum).abs().compareTo(new BigDecimal("0.02")) > 0;
    }

    private User reloadUserById(Integer id) {
        if (id == null) {
            return null;
        }
        return baseMapper.selectById(id);
    }

    @Override
    public boolean addBalance(Integer userId, BigDecimal amountYuan) {
        if (userId == null || amountYuan == null || amountYuan.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        boolean ok = baseMapper.addBalance(userId, amountYuan.setScale(2, RoundingMode.HALF_UP)) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean subtractBalanceIfEnough(Integer userId, BigDecimal amountYuan) {
        if (userId == null || amountYuan == null || amountYuan.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        boolean ok = baseMapper.subtractBalanceIfEnough(userId, amountYuan.setScale(2, RoundingMode.HALF_UP)) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean addGiftBalance(Integer userId, BigDecimal amountYuan) {
        if (userId == null || amountYuan == null || amountYuan.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        boolean ok = baseMapper.addGiftBalance(userId, amountYuan.setScale(2, RoundingMode.HALF_UP)) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean addBalanceAndGift(Integer userId, BigDecimal principalYuan, BigDecimal giftYuan) {
        if (userId == null) {
            return false;
        }
        BigDecimal p = principalYuan != null ? principalYuan.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        BigDecimal g = giftYuan != null ? giftYuan.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        if (p.compareTo(BigDecimal.ZERO) <= 0 && g.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        boolean ok = baseMapper.addBalanceAndGift(userId, p, g) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean subtractGiftBalanceIfEnough(Integer userId, BigDecimal amountYuan) {
        if (userId == null || amountYuan == null || amountYuan.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        boolean ok = baseMapper.subtractGiftBalanceIfEnough(userId, amountYuan.setScale(2, RoundingMode.HALF_UP)) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean subtractBalanceSplitIfEnough(Integer userId, BigDecimal principalYuan, BigDecimal giftYuan) {
        if (userId == null || principalYuan == null || giftYuan == null) {
            return false;
        }
        BigDecimal p = principalYuan.setScale(2, RoundingMode.HALF_UP);
        BigDecimal g = giftYuan.setScale(2, RoundingMode.HALF_UP);
        if (p.compareTo(BigDecimal.ZERO) < 0 || g.compareTo(BigDecimal.ZERO) < 0) {
            return false;
        }
        if (p.compareTo(BigDecimal.ZERO) == 0 && g.compareTo(BigDecimal.ZERO) == 0) {
            return false;
        }
        boolean ok = baseMapper.subtractBalanceSplitIfEnough(userId, p, g) > 0;
        if (ok) {
            reconcileUserBalanceTotal(userId);
        }
        return ok;
    }

    @Override
    public boolean subtractWalletProportionalIfEnough(Integer userId, BigDecimal totalYuan) {
        if (userId == null || totalYuan == null || totalYuan.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        User u = getById(userId);
        if (u == null) {
            return false;
        }
        BigDecimal payAmt = totalYuan.setScale(2, RoundingMode.HALF_UP);
        BigDecimal sum = nz(u.getPrincipal_balance()).add(nz(u.getGift_balance())).setScale(2, RoundingMode.HALF_UP);
        if (sum.compareTo(payAmt) < 0) {
            return false;
        }
        int payFen = UserWalletSplitUtil.yuanToFen(payAmt);
        int pFen = UserWalletSplitUtil.yuanToFen(u.getPrincipal_balance());
        int gFen = UserWalletSplitUtil.yuanToFen(u.getGift_balance());
        if (payFen <= 0 || pFen + gFen < payFen) {
            return false;
        }
        int[] split = UserWalletSplitUtil.splitConsumptionFen(payFen, pFen, gFen);
        return subtractBalanceSplitIfEnough(userId,
                UserWalletSplitUtil.fenToYuanBd(split[0]),
                UserWalletSplitUtil.fenToYuanBd(split[1]));
    }
}
