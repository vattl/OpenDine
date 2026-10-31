package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.toolkit.CollectionUtils;
import com.baomidou.mybatisplus.core.toolkit.StringUtils;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.config.InviteFirstOrderRewardSettings;
import com.lanf.dto.InviteCodeDTO;
import com.lanf.dto.InviteRecordDTO;
import com.lanf.dto.R;
import com.lanf.entity.Coupon;
import com.lanf.entity.InviteRecord;
import com.lanf.entity.Order;
import com.lanf.entity.User;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.InviteRecordMapper;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.InviteRewardClawbackService;

import com.lanf.service.IOrderService;
import com.lanf.service.InviteService;
import com.lanf.util.OrderNetRevenue;

import com.lanf.service.IUserService;
import cn.hutool.core.util.RandomUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 邀请服务实现类（具体业务逻辑）
 */
@Slf4j
@Service // 标识为Spring管理的Service Bean
@RequiredArgsConstructor // 构造器注入依赖（替代@Autowired）
public class InviteServiceImpl extends ServiceImpl<InviteRecordMapper, InviteRecord> implements InviteService {

    // 注入Mapper层依赖（通过构造器注入，由@RequiredArgsConstructor自动生成构造方法）
    private final InviteRecordMapper inviteRecordMapper;
    private final CouponMapper couponMapper;
    private final UserCouponMapper userCouponMapper;
    private final IUserService UserService;
    private final IOrderService orderService;
    private final InviteFirstOrderRewardSettings inviteFirstOrderRewardSettings;
    private final InviteRewardClawbackService inviteRewardClawbackService;
    /**
     * 实现：生成/获取用户专属邀请码
     */
    @Override
    public R<InviteCodeDTO> getInviteCode(String openid) {

        User user = UserService.getUserByOpenid(openid);
        if(user == null){
            return  R.fail("用户不存在");
        }
        // 查询用户是否已有邀请码

        if (!Objects.equals(user.getInvite_code(), "") && user.getInvite_code() != null) {
            InviteCodeDTO dto = new InviteCodeDTO();
            dto.setInvite_code(user.getInvite_code());
            return R.success(dto);
        }

        // 生成8位字母+数字邀请码（保证唯一）
        String inviteCode;
        int maxRetry = 10; // 最大重试次数（避免死循环）
        int retryCount = 0;

        do {
            // 方案1：纯数字邀请码（用户易记，推荐）
            inviteCode = RandomUtil.randomNumbers(8);

            // 方案2：数字+大小写字母（复杂度高，重复率更低）
            // inviteCode = RandomUtil.randomString(8);

            retryCount++;
            // 双重校验：邀请码非空 + 数据库不存在 + 未超过最大重试次数
            if (retryCount > maxRetry) {
                // 重试次数耗尽，抛出异常或返回默认值（根据业务处理）
                throw new RuntimeException("生成邀请码失败，已超过最大重试次数");
            }
        } while (UserService.selectByInvite_code(inviteCode) != null);

        user.setInvite_code(inviteCode);
        boolean updateSuccess = UserService.updateById(user);
        if (!updateSuccess) {
            return R.fail("生成邀请码失败，用户信息更新异常");
        }
        InviteCodeDTO dto = new InviteCodeDTO();
        dto.setInvite_code(inviteCode);
        return R.success(dto);
    }

    /**
     * 实现：获取用户邀请记录
     */
    @Override
    public R<List<InviteRecordDTO>> getInviteRecords(String openid) {

        List<InviteRecord> records = inviteRecordMapper.selectByInviterOpenid(openid);

        if (CollectionUtils.isEmpty(records)) {
            return R.success(Collections.emptyList());
        }
        List<InviteRecordDTO> dtoList = records.stream().map(record -> {
            InviteRecordDTO dto = new InviteRecordDTO();
            dto.setId(record.getId());
            dto.setStatus(record.getStatus());
            dto.setCreate_time(record.getCreate_time());
            dto.setReward_time(record.getReward_time());
            dto.setReward_id(record.getReward_id());
            dto.setReward_type(record.getReward_type());
            dto.setInvitee_openid(record.getInvitee_openid());
            dto.setFirst_order_reward_amount(record.getFirst_order_reward_amount());
            dto.setFirst_order_reward_time(record.getFirst_order_reward_time());
            dto.setFirst_order_no(record.getFirst_order_no());


            if (record.getInvitee_openid() != null && !record.getInvitee_openid().trim().isEmpty()) {
                User inviteeUser = UserService.getUserByOpenid(record.getInvitee_openid());
                if (inviteeUser != null) {
                    dto.setName(inviteeUser.getName()); // 真实昵称
                    dto.setPhone(inviteeUser.getPhone()); // 手机号
                    dto.setAvatar(inviteeUser.getAvatar()); // 真实头像
                } else {
                    // 兜底：被邀请人信息不存在时的默认值
                    dto.setName("已注销");
                    dto.setPhone("");
                    dto.setAvatar("");
                }
            } else {
                // 未注册的被邀请人
                dto.setName("未注册好友");
                dto.setPhone("");
                dto.setAvatar("");
            }

        return dto;
        }).collect(Collectors.toList());
        return R.success(dtoList);
    }

    /**
     * 获取用户奖励记录：邀请人为 openid，且已发过注册奖（{@code reward_time}）或首单余额返现（{@code first_order_reward_time}）。
     * 若同一条邀请记录两种奖励都有，拆成两行（注册礼 + 首单返现），返现行 {@code reward_type=first_order_balance}，
     * 列表唯一键见 {@link InviteRecordDTO#getReward_row_uid()}。
     */
    @Override
    public R<List<InviteRecordDTO>> getRewardRecords(String openid) {
        if (openid == null || openid.trim().isEmpty()) {
            return R.success(Collections.emptyList());
        }
        List<InviteRecord> records = list(new LambdaQueryWrapper<InviteRecord>()
                .eq(InviteRecord::getInviter_openid, openid)
                .and(w -> w.isNotNull(InviteRecord::getReward_time)
                        .or()
                        .isNotNull(InviteRecord::getFirst_order_reward_time))
                .last("ORDER BY COALESCE(reward_time, first_order_reward_time, create_time) DESC"));
        if (CollectionUtils.isEmpty(records)) {
            return R.success(Collections.emptyList());
        }
        List<InviteRecordDTO> dtoList = records.stream().map(record -> {
            InviteRecordDTO dto = new InviteRecordDTO();
            dto.setId(record.getId());
            dto.setStatus(record.getStatus());
            dto.setCreate_time(record.getCreate_time());
            dto.setReward_time(record.getReward_time());
            dto.setReward_id(record.getReward_id());
            dto.setReward_type(record.getReward_type());
            dto.setInvitee_openid(record.getInvitee_openid());
            dto.setFirst_order_reward_amount(record.getFirst_order_reward_amount());
            dto.setFirst_order_reward_time(record.getFirst_order_reward_time());
            dto.setFirst_order_no(record.getFirst_order_no());
            // reward_type=coupon 时根据 reward_id 查 t_coupon，返回优惠券名称与折扣
            if ("coupon".equals(record.getReward_type()) && record.getReward_id() != null) {
                Coupon coupon = couponMapper.selectById(record.getReward_id());
                if (coupon != null) {
                    dto.setCoupon_name(coupon.getCoupon_name());
                    dto.setCoupon_type(coupon.getCoupon_type());
                    dto.setDiscount_value(coupon.getDiscount_value());
                    dto.setMin_amount(coupon.getMin_amount());
                }
            }
            if (record.getInvitee_openid() != null && !record.getInvitee_openid().trim().isEmpty()) {
                User inviteeUser = UserService.getUserByOpenid(record.getInvitee_openid());
                if (inviteeUser != null) {
                    dto.setName(inviteeUser.getName());
                    dto.setPhone(inviteeUser.getPhone());
                    dto.setAvatar(inviteeUser.getAvatar());
                } else {
                    dto.setName("已注销");
                    dto.setPhone("");
                    dto.setAvatar("");
                }
            } else {
                dto.setName("未注册好友");
                dto.setPhone("");
                dto.setAvatar("");
            }
            return dto;
        }).collect(Collectors.toList());
        return R.success(expandInviteRewardRows(dtoList));
    }

    /**
     * 统一用户券失效时间：优先按 validity_time（小时）计算；为空或<=0时回退主券 end_time。
     */
    private Date calcUserCouponExpireTime(Coupon coupon) {
        if (coupon != null && coupon.getValidity_time() != null && coupon.getValidity_time() > 0) {
            Calendar calendar = Calendar.getInstance();
            calendar.add(Calendar.HOUR_OF_DAY, coupon.getValidity_time());
            return calendar.getTime();
        }
        return coupon != null ? coupon.getEnd_time() : null;
    }
    /**
     * 实现：被邀请者注册成功后，发放奖励
     */
    @Override
    @Transactional(rollbackFor = Exception.class) // 明确捕获所有异常，保证事务回滚
    public void giveReward(String invite_code, String invitee_openid) {
        // 1. 查询邀请记录（并锁定，防止并发修改：悲观锁，适用于高并发奖励发放场景）
        // 关键：添加状态判断（status=0 未发放奖励），避免重复处理
        InviteRecord record = inviteRecordMapper.selectOne(
                new LambdaQueryWrapper<InviteRecord>()
                        .eq(InviteRecord::getInvite_code, invite_code)
                        .eq(InviteRecord::getInvitee_openid, invitee_openid)
                        .eq(InviteRecord::getStatus, 0) // 0：未发放奖励，1：已发放，2：失效
                        .last("FOR UPDATE") // 悲观锁：锁定该记录，其他线程需等待释放
        );
        if (record == null) {
            // 无有效邀请记录（已发放/无效/不存在），直接返回
            return;
        }

        // 2. 缓存优惠券信息，避免重复查询数据库
        Coupon inviteFriendCoupon = getCouponByName("邀请好友奖励券");
        Coupon newUserCoupon = getCouponByName("新用户注册券");

        // 3. 给邀请者发放【邀请好友奖励券】
        if (inviteFriendCoupon != null) {
            // 3.1 校验优惠券库存（若为限量优惠券）
            if (inviteFriendCoupon.getStock() != -1 && inviteFriendCoupon.getStock() <= 0) {
                throw new RuntimeException("邀请好友奖励券库存不足");
            }

            // 3.2 保存邀请者优惠券（无并发重复风险：已通过悲观锁锁定邀请记录，同一邀请记录仅能被一个线程处理）
            UserCoupon inviterUserCoupon = new UserCoupon();
            inviterUserCoupon.setUser_openid(record.getInviter_openid());
            inviterUserCoupon.setCoupon_id(inviteFriendCoupon.getId());
            inviterUserCoupon.setGet_time(new Date());
            inviterUserCoupon.setStatus(0);
            inviterUserCoupon.setExpire_time(calcUserCouponExpireTime(inviteFriendCoupon));
            userCouponMapper.insert(inviterUserCoupon);
            couponMapper.incrementGrantedCount(inviteFriendCoupon.getId());

            // 3.3 更新邀请记录（奖励信息 + 发放时间）
            record.setReward_time(new Date());
            record.setReward_type("coupon");
            record.setReward_id(inviteFriendCoupon.getId());
            record.setStatus(1); // 标记为已发放奖励
            inviteRecordMapper.updateById(record);

            // 3.4 更新优惠券库存（若为限量优惠券）
            if (inviteFriendCoupon.getStock() != -1) {
                inviteFriendCoupon.setStock(inviteFriendCoupon.getStock() - 1);
                couponMapper.updateById(inviteFriendCoupon);
            }
        }

        // 4. 给被邀请者发放【新用户注册券】（解决并发重复发放问题）
        if (newUserCoupon != null) {
            // 4.1 校验优惠券库存
            if (newUserCoupon.getStock() != -1 && newUserCoupon.getStock() <= 0) {
                throw new RuntimeException("新用户注册券库存不足");
            }

            // 4.2 插入用户优惠券（通过「唯一索引 + 异常捕获」解决并发重复插入）
            UserCoupon inviteeUserCoupon = new UserCoupon();
            inviteeUserCoupon.setUser_openid(invitee_openid); // 修正：使用被邀请者openid
            inviteeUserCoupon.setCoupon_id(newUserCoupon.getId());
            inviteeUserCoupon.setGet_time(new Date());
            inviteeUserCoupon.setStatus(0);
            inviteeUserCoupon.setExpire_time(calcUserCouponExpireTime(newUserCoupon));

            try {
                userCouponMapper.insert(inviteeUserCoupon);
                couponMapper.incrementGrantedCount(newUserCoupon.getId());

                // 4.3 更新新用户优惠券库存（若为限量优惠券）
                if (newUserCoupon.getStock() != -1) {
                    newUserCoupon.setStock(newUserCoupon.getStock() - 1);
                    couponMapper.updateById(newUserCoupon);
                }
            } catch (DuplicateKeyException e) {
                // 捕获唯一索引冲突异常，说明该用户已领取过该优惠券，无需处理（不抛异常，不影响其他逻辑）
                return;
            }
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void tryGrantInviterBalanceForInviteeFirstPaidOrder(Order paidOrder, double paidYuan) {
        if (paidOrder == null || paidYuan <= 0d || Double.isNaN(paidYuan) || !inviteFirstOrderRewardSettings.isEnabled()) {
            return;
        }
        if (paidOrder.getId() == null) {
            return;
        }
        String consumerOpenid = resolveConsumerOpenid(paidOrder);
        if (StringUtils.isBlank(consumerOpenid)) {
            return;
        }
        Order earliest = orderService.getOne(
                new LambdaQueryWrapper<Order>()
                        .eq(Order::getTransac_status, "success")
                        .and(w -> w.eq(Order::getOpenid, consumerOpenid).or().eq(Order::getPay_openid, consumerOpenid))
                        .orderByAsc(Order::getPay_time)
                        .orderByAsc(Order::getId)
                        .last("LIMIT 1"));
        if (earliest == null || !paidOrder.getId().equals(earliest.getId())) {
            return;
        }
        InviteRecord record = getOne(
                new LambdaQueryWrapper<InviteRecord>()
                        .eq(InviteRecord::getInvitee_openid, consumerOpenid)
                        .eq(InviteRecord::getStatus, 1)
                        .isNull(InviteRecord::getFirst_order_reward_time)
                        .orderByAsc(InviteRecord::getCreate_time)
                        .last("LIMIT 1"));
        if (record == null) {
            return;
        }
        User inviter = UserService.getUserByOpenid(record.getInviter_openid());
        if (inviter == null || inviter.getId() == null) {
            log.warn("邀请首单余额返利：邀请人不存在 inviterOpenid={}", record.getInviter_openid());
            return;
        }
        double pct = inviteFirstOrderRewardSettings.getRewardPercent();
        BigDecimal rewardBd = computeInviteRewardIntegerYuan(paidYuan, pct);
        Date now = new Date();
        LambdaUpdateWrapper<InviteRecord> uw = new LambdaUpdateWrapper<InviteRecord>()
                .eq(InviteRecord::getId, record.getId())
                .isNull(InviteRecord::getFirst_order_reward_time)
                .set(InviteRecord::getFirst_order_reward_amount, rewardBd.doubleValue())
                .set(InviteRecord::getFirst_order_reward_time, now)
                .set(InviteRecord::getFirst_order_no, paidOrder.getOrder_no());
        int rows = inviteRecordMapper.update(null, uw);
        if (rows != 1) {
            return;
        }
        if (rewardBd.compareTo(BigDecimal.ZERO) <= 0) {
            log.info("邀请首单余额返利：折算金额为0，仅标记记录 inviteRecordId={} orderNo={}", record.getId(), paidOrder.getOrder_no());
            return;
        }
        boolean ok = UserService.addGiftBalance(inviter.getId(), rewardBd);
        if (!ok) {
            throw new IllegalStateException("邀请首单余额返利加赠送金失败 userId=" + inviter.getId());
        }
        log.info("邀请首单余额返利成功 inviterOpenid={} inviteeOpenid={} orderNo={} paidYuan={} rewardYuan={}",
                record.getInviter_openid(), consumerOpenid, paidOrder.getOrder_no(), paidYuan, rewardBd);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void reconcileFirstOrderInviteRewardOnRefund(Order orderAfterRefundUpdate) {
        if (orderAfterRefundUpdate == null || StringUtils.isBlank(orderAfterRefundUpdate.getOrder_no())) {
            return;
        }
        String orderNo = orderAfterRefundUpdate.getOrder_no().trim();
        InviteRecord record =
                inviteRecordMapper.selectByFirstOrderNoForUpdate(orderNo);
        if (record == null) {
            return;
        }

        double totalPaidYuan = orderPayableYuan(orderAfterRefundUpdate);
        if (totalPaidYuan <= 0d) {
            return;
        }
        int totalPaidFen = (int) Math.round(totalPaidYuan * 100d);
        double refundedYuan = orderAfterRefundUpdate.getRefund_amount() != null ? orderAfterRefundUpdate.getRefund_amount() : 0d;
        int refundedFen = (int) Math.round(refundedYuan * 100d);
        int remainingFen = Math.max(0, totalPaidFen - refundedFen);
        double remainingYuan = remainingFen / 100.0;

        boolean effectivelyFullRefund = remainingFen <= 0;
        double pct = inviteFirstOrderRewardSettings.isEnabled() ? inviteFirstOrderRewardSettings.getRewardPercent() : 0d;
        BigDecimal newRewardBd = computeInviteRewardIntegerYuan(remainingYuan, pct);

        BigDecimal oldRewardBd = BigDecimal.valueOf(record.getFirst_order_reward_amount() != null ? record.getFirst_order_reward_amount() : 0d)
                .setScale(0, RoundingMode.HALF_UP);
        BigDecimal deltaBd = newRewardBd.subtract(oldRewardBd);

        User inviter = UserService.getUserByOpenid(record.getInviter_openid());
        if (inviter == null || inviter.getId() == null) {
            throw new IllegalStateException(
                    "邀请首单返现退款冲正失败：邀请人不存在 " + record.getInviter_openid());
        }

        if (deltaBd.compareTo(BigDecimal.ZERO) < 0) {
            BigDecimal claw = deltaBd.negate();
            if (claw.compareTo(BigDecimal.ZERO) > 0) {
                if (!UserService.subtractGiftBalanceIfEnough(inviter.getId(), claw.setScale(2, RoundingMode.HALF_UP))) {
                    inviteRewardClawbackService.recordDebt(
                            record.getId(),
                            inviter.getId(),
                            orderNo,
                            claw);
                    log.warn(
                            "邀请首单返现退款冲正转入持久化待收回队列 "
                                    + "inviteRecordId={} userId={} amountYuan={}",
                            record.getId(), inviter.getId(), claw);
                }
            }
        } else if (deltaBd.compareTo(BigDecimal.ZERO) > 0) {
            if (!UserService.addGiftBalance(inviter.getId(), deltaBd.setScale(2, RoundingMode.HALF_UP))) {
                throw new IllegalStateException(
                        "邀请首单返现退款冲正失败：赠送金增加失败 userId="
                                + inviter.getId() + " amountYuan=" + deltaBd);
            }
        }

        if (effectivelyFullRefund) {
            LambdaUpdateWrapper<InviteRecord> uw = new LambdaUpdateWrapper<InviteRecord>()
                    .eq(InviteRecord::getId, record.getId())
                    .set(InviteRecord::getFirst_order_reward_amount, null)
                    .set(InviteRecord::getFirst_order_no, null);
            if (inviteRecordMapper.update(null, uw) != 1) {
                throw new IllegalStateException("邀请首单返现退款冲正记录更新失败");
            }
            log.info("邀请首单返现退款冲正：全单退款，已收回返现并取消首单资格 inviteRecordId={} orderNo={} revokeYuan={}",
                    record.getId(), orderNo, oldRewardBd);
        } else {
            record.setFirst_order_reward_amount(newRewardBd.doubleValue());
            if (inviteRecordMapper.updateById(record) != 1) {
                throw new IllegalStateException("邀请首单返现退款冲正记录更新失败");
            }
            log.info("邀请首单返现退款冲正：部分退款 inviteRecordId={} orderNo={} remainingYuan={} newRewardYuan={} deltaYuan={}",
                    record.getId(), orderNo, remainingYuan, newRewardBd, deltaBd);
        }
    }

    /** 与营业额一致（不含已退）：sett - discount + service - pay_amount_gift；退款在冲正逻辑中另减 */
    private static double orderPayableYuan(Order o) {
        return OrderNetRevenue.storeLineBeforeRefundYuan(o);
    }

    /** 返现整数元，四舍五入 */
    private static BigDecimal computeInviteRewardIntegerYuan(double paidYuan, double pct) {
        if (paidYuan <= 0d || Double.isNaN(paidYuan) || pct <= 0d || Double.isNaN(pct)) {
            return BigDecimal.ZERO;
        }
        return BigDecimal.valueOf(paidYuan)
                .multiply(BigDecimal.valueOf(pct))
                .divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
    }

    private static String resolveConsumerOpenid(Order paidOrder) {
        if (paidOrder.getOpenid() != null && !paidOrder.getOpenid().trim().isEmpty()) {
            return paidOrder.getOpenid().trim();
        }
        if (paidOrder.getPay_openid() != null && !paidOrder.getPay_openid().trim().isEmpty()) {
            return paidOrder.getPay_openid().trim();
        }
        return null;
    }

    /**
     * 将「一条邀请记录」展开为奖励列表行：同时有注册礼与首单返现时拆两行，并为返现行标注 {@code reward_type=first_order_balance}。
     */
    private static List<InviteRecordDTO> expandInviteRewardRows(List<InviteRecordDTO> rows) {
        if (CollectionUtils.isEmpty(rows)) {
            return Collections.emptyList();
        }
        List<InviteRecordDTO> out = new ArrayList<>(rows.size() * 2);
        for (InviteRecordDTO dto : rows) {
            String base = dto.getId() != null ? String.valueOf(dto.getId()) : "noid";
            boolean hasReg = dto.getReward_time() != null;
            boolean hasCash = dto.getFirst_order_reward_time() != null;
            if (hasReg && hasCash) {
                InviteRecordDTO reg = cloneInviteRecordDto(dto);
                stripFirstOrderCashbackFields(reg);
                reg.setReward_row_uid(base + "-reg");
                out.add(reg);
                InviteRecordDTO cash = cloneInviteRecordDto(dto);
                stripRegisterRewardFields(cash);
                cash.setReward_type("first_order_balance");
                cash.setReward_row_uid(base + "-cash");
                out.add(cash);
            } else {
                dto.setReward_row_uid(base + "-full");
                if (hasCash && !hasReg) {
                    dto.setReward_type("first_order_balance");
                }
                out.add(dto);
            }
        }
        out.sort(Comparator.comparing(InviteServiceImpl::rewardRowSortTime).reversed());
        return out;
    }

    private static Date rewardRowSortTime(InviteRecordDTO d) {
        Date fb = d.getCreate_time() != null ? d.getCreate_time() : new Date(0L);
        String uid = d.getReward_row_uid();
        if (uid != null && uid.endsWith("-reg")) {
            return d.getReward_time() != null ? d.getReward_time() : fb;
        }
        if (uid != null && uid.endsWith("-cash")) {
            return d.getFirst_order_reward_time() != null ? d.getFirst_order_reward_time() : fb;
        }
        Date m = laterOfNullable(d.getReward_time(), d.getFirst_order_reward_time());
        return m != null ? m : fb;
    }

    private static Date laterOfNullable(Date a, Date b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a.after(b) ? a : b;
    }

    private static InviteRecordDTO cloneInviteRecordDto(InviteRecordDTO src) {
        InviteRecordDTO d = new InviteRecordDTO();
        BeanUtils.copyProperties(src, d);
        return d;
    }

    private static void stripFirstOrderCashbackFields(InviteRecordDTO d) {
        d.setFirst_order_reward_amount(null);
        d.setFirst_order_reward_time(null);
        d.setFirst_order_no(null);
    }

    private static void stripRegisterRewardFields(InviteRecordDTO d) {
        d.setReward_time(null);
        d.setReward_id(null);
        d.setReward_type(null);
        d.setCoupon_name(null);
        d.setCoupon_type(null);
        d.setDiscount_value(null);
        d.setMin_amount(null);
    }

    /**
     * 缓存优惠券查询，避免重复IO
     * @param couponName 优惠券名称
     * @return 有效优惠券
     */
    private Coupon getCouponByName(String couponName) {
        return couponMapper.selectOne(
                new LambdaQueryWrapper<Coupon>()
                        .eq(Coupon::getCoupon_name, couponName)
                        .eq(Coupon::getStatus, 1) // 1：有效优惠券
                        .ge(Coupon::getEnd_time,new Date())
                        .last("LIMIT 1")
        );
    }
}
