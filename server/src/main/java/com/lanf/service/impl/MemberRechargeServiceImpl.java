package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.User;
import com.lanf.mapper.MemberRechargeMapper;
import com.lanf.mapper.UserMapper;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.MemberRechargeSummary;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

@Service
public class MemberRechargeServiceImpl extends ServiceImpl<MemberRechargeMapper, MemberRecharge> implements IMemberRechargeService {

    @Autowired(required = false)
    private UserMapper userMapper;

    private static BigDecimal nz(BigDecimal v) {
        if (v == null) {
            return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    @Override
    public Long createPendingWechat(Integer userId, String openid, String orderNo, Integer shopId,
                                    BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan) {
        BigDecimal r = nz(rechargeAmountYuan);
        BigDecimal g = nz(giftAmountYuan);
        if (g.compareTo(BigDecimal.ZERO) < 0) {
            g = BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        MemberRecharge m = new MemberRecharge();
        m.setUser_id(userId);
        m.setOpenid(openid);
        m.setOrder_no(orderNo);
        m.setShop_id(shopId);
        m.setChannel("wechat");
        m.setStatus("pending");
        m.setRecharge_amount(r);
        m.setGift_amount(g);
        m.setTotal_amount(r.add(g));
        save(m);
        return m.getId();
    }

    @Override
    public void updateOrderNo(String oldOrderNo, String newOrderNo) {
        if (!StringUtils.hasText(oldOrderNo) || !StringUtils.hasText(newOrderNo) || oldOrderNo.equals(newOrderNo)) {
            return;
        }
        update(new UpdateWrapper<MemberRecharge>().set("order_no", newOrderNo).eq("order_no", oldOrderNo));
    }

    @Override
    public boolean markSuccessWechat(String orderNo, String transactionId, Date payTime) {
        if (!StringUtils.hasText(orderNo)) {
            return false;
        }
        return update(new UpdateWrapper<MemberRecharge>()
                .set("status", "success")
                .set("transaction_id", transactionId)
                .set("pay_time", payTime)
                .eq("order_no", orderNo)
                .eq("status", "pending"));
    }

    @Override
    public void markCancelledById(Long id) {
        if (id == null) {
            return;
        }
        update(new UpdateWrapper<MemberRecharge>().set("status", "cancelled").eq("id", id).eq("status", "pending"));
    }

    @Override
    public void markCancelledByOrderNo(String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return;
        }
        update(new UpdateWrapper<MemberRecharge>().set("status", "cancelled").eq("order_no", orderNo).eq("status", "pending"));
    }

    @Override
    public boolean cancelPendingWechat(String rechargeNo, String openid) {
        if (!StringUtils.hasText(rechargeNo) || !StringUtils.hasText(openid)) {
            return false;
        }
        return update(new UpdateWrapper<MemberRecharge>()
                .set("status", "cancelled")
                .eq("order_no", rechargeNo.trim())
                .eq("openid", openid.trim())
                .eq("channel", "wechat")
                .eq("status", "pending"));
    }

    @Override
    public void recordAdminSuccess(Integer userId, String openid, BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark) {
        recordAdminSuccess(userId, openid, null, rechargeAmountYuan, giftAmountYuan, remark);
    }

    @Override
    public void recordAdminSuccess(Integer userId, String openid, Integer shopId,
                                   BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark) {
        recordAdminSuccess(userId, openid, shopId, null, null, rechargeAmountYuan, giftAmountYuan, remark);
    }

    @Override
    public void recordAdminSuccess(Integer userId, String openid, Integer shopId, Integer operatorId, Long drawerSessionId,
                                   BigDecimal rechargeAmountYuan, BigDecimal giftAmountYuan, String remark) {
        BigDecimal r = nz(rechargeAmountYuan);
        BigDecimal g = nz(giftAmountYuan);
        if (g.compareTo(BigDecimal.ZERO) < 0) {
            g = BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        BigDecimal total = r.add(g).setScale(2, RoundingMode.HALF_UP);
        MemberRecharge m = new MemberRecharge();
        m.setUser_id(userId);
        m.setOpenid(openid);
        m.setOrder_no(null);
        m.setShop_id(shopId);
        m.setOperator_id(operatorId);
        m.setDrawer_session_id(drawerSessionId);
        m.setChannel("admin");
        m.setStatus("success");
        m.setRecharge_amount(r);
        m.setGift_amount(g);
        m.setTotal_amount(total);
        m.setTransaction_id(null);
        m.setPay_time(new Date());
        m.setRemark(remark);
        save(m);
    }

    @Override
    public MemberRechargeSummary summarizeSuccessfulByWindow(Integer shopId, Date startInclusive, Date endExclusive) {
        if (shopId == null || startInclusive == null || endExclusive == null) {
            return MemberRechargeSummary.empty();
        }
        return fromAggregate(baseMapper.summarizeSuccessfulByWindow(shopId, startInclusive, endExclusive));
    }

    @Override
    public MemberRechargeSummary summarizeSuccessfulByDrawerSession(Long drawerSessionId) {
        if (drawerSessionId == null) {
            return MemberRechargeSummary.empty();
        }
        return fromAggregate(baseMapper.summarizeSuccessfulByDrawerSession(drawerSessionId));
    }

    private static MemberRechargeSummary fromAggregate(Map<String, Object> aggregate) {
        if (aggregate == null || aggregate.isEmpty()) {
            return MemberRechargeSummary.empty();
        }
        return new MemberRechargeSummary(
                number(aggregate.get("success_count")).longValue(),
                toFen(decimal(aggregate.get("principal_amount"))),
                toFen(decimal(aggregate.get("gift_amount"))));
    }

    private static long toFen(BigDecimal yuan) {
        return nz(yuan).movePointRight(2).longValueExact();
    }

    private static Number number(Object value) {
        return value instanceof Number ? (Number) value : 0L;
    }

    private static BigDecimal decimal(Object value) {
        if (value instanceof BigDecimal) return (BigDecimal) value;
        if (value instanceof Number) return new BigDecimal(value.toString());
        return BigDecimal.ZERO;
    }

    @Override
    public IPage<MemberRecharge> pageByOpenid(String openid, int page, int pageSize, String statusFilter) {
        QueryWrapper<MemberRecharge> q = new QueryWrapper<MemberRecharge>()
                .eq("openid", openid)
                .orderByDesc("created_at");
        if (StringUtils.hasText(statusFilter) && !"all".equalsIgnoreCase(statusFilter.trim())) {
            q.eq("status", statusFilter.trim().toLowerCase());
        }
        IPage<MemberRecharge> pg = page(new Page<>(page, pageSize), q);
        attachMemberPhones(pg.getRecords());
        return pg;
    }

    @Override
    public void attachMemberPhones(List<MemberRecharge> records) {
        if (records == null || records.isEmpty() || userMapper == null) {
            return;
        }
        Set<Integer> userIds = new HashSet<>();
        Set<String> openids = new HashSet<>();
        for (MemberRecharge r : records) {
            if (r == null) continue;
            if (r.getUser_id() != null && r.getUser_id() > 0) {
                userIds.add(r.getUser_id());
            } else if (StringUtils.hasText(r.getOpenid())) {
                openids.add(r.getOpenid().trim());
            }
        }
        Map<Integer, String> phoneByUserId = new HashMap<>();
        Map<String, String> phoneByOpenid = new HashMap<>();

        if (!userIds.isEmpty()) {
            List<User> users = userMapper.selectBatchIds(userIds);
            if (users != null) {
                for (User u : users) {
                    if (u != null && StringUtils.hasText(u.getPhone())) {
                        if (u.getId() != null) {
                            phoneByUserId.put(u.getId(), u.getPhone().trim());
                        }
                        if (StringUtils.hasText(u.getOpenid())) {
                            phoneByOpenid.put(u.getOpenid().trim(), u.getPhone().trim());
                        }
                    }
                }
            }
        }

        Set<String> remainingOpenids = new HashSet<>();
        for (MemberRecharge r : records) {
            if (r == null) continue;
            boolean hasPhone = (r.getUser_id() != null && phoneByUserId.containsKey(r.getUser_id()));
            if (!hasPhone && StringUtils.hasText(r.getOpenid())) {
                String oid = r.getOpenid().trim();
                if (!phoneByOpenid.containsKey(oid)) {
                    remainingOpenids.add(oid);
                }
            }
        }

        if (!remainingOpenids.isEmpty()) {
            List<User> users = userMapper.selectList(new QueryWrapper<User>().in("openid", remainingOpenids));
            if (users != null) {
                for (User u : users) {
                    if (u != null && StringUtils.hasText(u.getPhone())) {
                        if (StringUtils.hasText(u.getOpenid())) {
                            phoneByOpenid.put(u.getOpenid().trim(), u.getPhone().trim());
                        }
                        if (u.getId() != null) {
                            phoneByUserId.put(u.getId(), u.getPhone().trim());
                        }
                    }
                }
            }
        }

        for (MemberRecharge r : records) {
            if (r == null) continue;
            String phone = null;
            if (r.getUser_id() != null) {
                phone = phoneByUserId.get(r.getUser_id());
            }
            if (!StringUtils.hasText(phone) && StringUtils.hasText(r.getOpenid())) {
                phone = phoneByOpenid.get(r.getOpenid().trim());
            }
            r.setPhone(phone);
        }
    }
}
