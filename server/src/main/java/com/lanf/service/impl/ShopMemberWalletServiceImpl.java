package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.MemberCrossShopClearing;
import com.lanf.entity.ShopMemberWallet;
import com.lanf.entity.SystemConfig;
import com.lanf.entity.User;
import com.lanf.mapper.MemberCrossShopClearingMapper;
import com.lanf.mapper.ShopMemberWalletMapper;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.service.IShopMemberWalletService;
import com.lanf.service.IUserService;
import com.lanf.util.SystemConfigTableSupport;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

@Service
public class ShopMemberWalletServiceImpl extends ServiceImpl<ShopMemberWalletMapper, ShopMemberWallet>
        implements IShopMemberWalletService {

    private static final Logger log = LoggerFactory.getLogger(ShopMemberWalletServiceImpl.class);

    @Autowired
    private SystemConfigMapper systemConfigMapper;

    @Autowired
    private SystemConfigTableSupport systemConfigTableSupport;

    @Autowired
    private MemberCrossShopClearingMapper crossShopClearingMapper;

    @Autowired(required = false)
    private IUserService userService;

    @Override
    public boolean isCrossShopBalanceEnabled(Integer shopId) {
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 0;
        try {
            SystemConfig cfg = systemConfigMapper.selectByShopAndKey(targetShopId, CONFIG_KEY_CROSS_SHOP_BALANCE);
            if (cfg == null && targetShopId != 0) {
                cfg = systemConfigMapper.selectByShopAndKey(0, CONFIG_KEY_CROSS_SHOP_BALANCE);
            }
            if (cfg == null) {
                // 默认开启跨店互通（连锁共享模式）
                return true;
            }
            String val = cfg.getConfig_value();
            return "1".equals(val) || "true".equalsIgnoreCase(val);
        } catch (Exception e) {
            log.warn("Failed to check cross-shop balance config for shop {}, defaulting to true: {}", shopId, e.getMessage());
            return true;
        }
    }

    @Override
    public void setCrossShopBalanceEnabled(int shopId, boolean enabled) {
        String val = enabled ? "1" : "0";
        String remark = enabled ? "允许跨店使用会员余额" : "禁止跨店使用会员余额（单店专属）";
        if (systemConfigTableSupport.hasShopIdColumn()) {
            SystemConfig existing = systemConfigMapper.selectByShopAndKey(shopId, CONFIG_KEY_CROSS_SHOP_BALANCE);
            if (existing == null) {
                SystemConfig cfg = new SystemConfig();
                cfg.setShop_id(shopId);
                cfg.setConfig_key(CONFIG_KEY_CROSS_SHOP_BALANCE);
                cfg.setConfig_value(val);
                cfg.setRemark(remark);
                systemConfigMapper.insert(cfg);
            } else {
                existing.setConfig_value(val);
                existing.setRemark(remark);
                systemConfigMapper.updateById(existing);
            }
        } else {
            SystemConfig legacy = systemConfigMapper.selectLegacyByKey(CONFIG_KEY_CROSS_SHOP_BALANCE);
            if (legacy == null) {
                systemConfigMapper.insertLegacy(CONFIG_KEY_CROSS_SHOP_BALANCE, val, remark);
            } else {
                systemConfigMapper.updateLegacy(CONFIG_KEY_CROSS_SHOP_BALANCE, val, remark);
            }
        }
    }

    @Override
    public BigDecimal getAvailableBalanceForShop(Integer userId, Integer shopId) {
        if (userId == null || shopId == null) {
            return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        ShopMemberWallet wallet = baseMapper.selectByUserAndShop(userId, shopId);
        if (wallet != null) {
            BigDecimal p = wallet.getPrincipal_balance() != null ? wallet.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal g = wallet.getGift_balance() != null ? wallet.getGift_balance() : BigDecimal.ZERO;
            return p.add(g).setScale(2, RoundingMode.HALF_UP);
        }
        // 如果该用户在 t_shop_member_wallet 无任何记录，可能是历史用户，检查总余额
        List<ShopMemberWallet> anyWallets = baseMapper.selectWalletsWithBalance(userId);
        if (anyWallets == null || anyWallets.isEmpty()) {
            if (userService != null) {
                User u = userService.getById(userId);
                if (u != null && u.getBalance() != null && u.getBalance().compareTo(BigDecimal.ZERO) > 0) {
                    // 历史用户默认将余额归属默认门店(shopId=1)
                    if (shopId == 1) {
                        return u.getBalance().setScale(2, RoundingMode.HALF_UP);
                    }
                }
            }
        }
        return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void addBalance(Integer userId, Integer shopId, BigDecimal principal, BigDecimal gift) {
        if (userId == null) return;
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;
        BigDecimal p = principal != null ? principal.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        BigDecimal g = gift != null ? gift.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);

        ShopMemberWallet wallet = baseMapper.selectByUserAndShop(userId, targetShopId);
        if (wallet == null) {
            wallet = ShopMemberWallet.builder()
                    .user_id(userId)
                    .shop_id(targetShopId)
                    .principal_balance(p)
                    .gift_balance(g)
                    .total_recharge_principal(p)
                    .total_recharge_gift(g)
                    .created_at(new Date())
                    .updated_at(new Date())
                    .build();
            baseMapper.insert(wallet);
        } else {
            BigDecimal curP = wallet.getPrincipal_balance() != null ? wallet.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal curG = wallet.getGift_balance() != null ? wallet.getGift_balance() : BigDecimal.ZERO;
            BigDecimal totP = wallet.getTotal_recharge_principal() != null ? wallet.getTotal_recharge_principal() : BigDecimal.ZERO;
            BigDecimal totG = wallet.getTotal_recharge_gift() != null ? wallet.getTotal_recharge_gift() : BigDecimal.ZERO;

            wallet.setPrincipal_balance(curP.add(p));
            wallet.setGift_balance(curG.add(g));
            wallet.setTotal_recharge_principal(totP.add(p));
            wallet.setTotal_recharge_gift(totG.add(g));
            wallet.setUpdated_at(new Date());
            baseMapper.updateById(wallet);
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean deductBalance(Integer userId, Integer shopId, BigDecimal amount) {
        if (userId == null || amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;
        ShopMemberWallet wallet = baseMapper.selectByUserAndShop(userId, targetShopId);
        if (wallet == null) {
            return false;
        }
        BigDecimal p = wallet.getPrincipal_balance() != null ? wallet.getPrincipal_balance() : BigDecimal.ZERO;
        BigDecimal g = wallet.getGift_balance() != null ? wallet.getGift_balance() : BigDecimal.ZERO;
        BigDecimal total = p.add(g);
        if (total.compareTo(amount) < 0) {
            return false;
        }
        // 优先扣减本金，本金不足扣赠送
        BigDecimal deductP = p.min(amount);
        BigDecimal deductG = amount.subtract(deductP);
        wallet.setPrincipal_balance(p.subtract(deductP));
        wallet.setGift_balance(g.subtract(deductG));
        wallet.setUpdated_at(new Date());
        return baseMapper.updateById(wallet) > 0;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean deductAndClearBalance(Integer userId, Integer consumeShopId, BigDecimal principal, BigDecimal gift, String orderNo) {
        if (userId == null || consumeShopId == null) {
            return false;
        }
        BigDecimal remP = principal != null ? principal.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO;
        BigDecimal remG = gift != null ? gift.setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO;

        // 1. 先尝试从本消费门店钱包扣减
        ShopMemberWallet localWallet = baseMapper.selectByUserAndShop(userId, consumeShopId);
        if (localWallet != null) {
            BigDecimal locP = localWallet.getPrincipal_balance() != null ? localWallet.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal locG = localWallet.getGift_balance() != null ? localWallet.getGift_balance() : BigDecimal.ZERO;

            BigDecimal useP = locP.min(remP);
            BigDecimal useG = locG.min(remG);

            localWallet.setPrincipal_balance(locP.subtract(useP));
            localWallet.setGift_balance(locG.subtract(useG));
            localWallet.setUpdated_at(new Date());
            baseMapper.updateById(localWallet);

            remP = remP.subtract(useP);
            remG = remG.subtract(useG);
        }

        // 如果本门店钱包已足够扣减，不需要跨店清算
        if (remP.compareTo(BigDecimal.ZERO) <= 0 && remG.compareTo(BigDecimal.ZERO) <= 0) {
            return true;
        }

        // 2. 本门店不足，需要跨店扣减
        List<ShopMemberWallet> otherWallets = baseMapper.selectWalletsWithBalance(userId);
        for (ShopMemberWallet other : otherWallets) {
            if (other.getShop_id().equals(consumeShopId)) {
                continue;
            }
            if (remP.compareTo(BigDecimal.ZERO) <= 0 && remG.compareTo(BigDecimal.ZERO) <= 0) {
                break;
            }
            BigDecimal oP = other.getPrincipal_balance() != null ? other.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal oG = other.getGift_balance() != null ? other.getGift_balance() : BigDecimal.ZERO;

            BigDecimal useP = oP.min(remP);
            BigDecimal useG = oG.min(remG);

            if (useP.compareTo(BigDecimal.ZERO) > 0 || useG.compareTo(BigDecimal.ZERO) > 0) {
                other.setPrincipal_balance(oP.subtract(useP));
                other.setGift_balance(oG.subtract(useG));
                other.setUpdated_at(new Date());
                baseMapper.updateById(other);

                remP = remP.subtract(useP);
                remG = remG.subtract(useG);

                // 记录跨店清算
                BigDecimal crossTotal = useP.add(useG);
                MemberCrossShopClearing clearing = MemberCrossShopClearing.builder()
                        .order_no(orderNo)
                        .user_id(userId)
                        .source_shop_id(other.getShop_id())
                        .consume_shop_id(consumeShopId)
                        .principal_amount(useP)
                        .gift_amount(useG)
                        .total_amount(crossTotal)
                        .clearing_status(MemberCrossShopClearing.STATUS_PENDING)
                        .created_at(new Date())
                        .build();
                crossShopClearingMapper.insert(clearing);
                log.info("Cross-shop balance clearing recorded: order={}, user={}, sourceShop={}, consumeShop={}, amt={}",
                        orderNo, userId, other.getShop_id(), consumeShopId, crossTotal);
            }
        }
        return true;
    }

    @Override
    public Map<String, Object> getCrossShopClearingReport(Integer shopId, String startDate, String endDate) {
        List<Map<String, Object>> summaries = crossShopClearingMapper.summarizeCrossShopClearing(shopId, startDate, endDate);

        BigDecimal crossInflowAmount = BigDecimal.ZERO;  // 应收：他店充值，本店消费
        BigDecimal crossOutflowAmount = BigDecimal.ZERO; // 应付：本店充值，他店消费
        int inflowOrders = 0;
        int outflowOrders = 0;

        List<Map<String, Object>> partnerBreakdown = new ArrayList<>();

        if (summaries != null) {
            for (Map<String, Object> row : summaries) {
                Integer src = row.get("source_shop_id") instanceof Number ? ((Number) row.get("source_shop_id")).intValue() : null;
                Integer csm = row.get("consume_shop_id") instanceof Number ? ((Number) row.get("consume_shop_id")).intValue() : null;
                BigDecimal tot = row.get("total_amount") instanceof Number ? BigDecimal.valueOf(((Number) row.get("total_amount")).doubleValue()).setScale(2, RoundingMode.HALF_UP) : BigDecimal.ZERO;
                int count = row.get("order_count") instanceof Number ? ((Number) row.get("order_count")).intValue() : 0;

                if (shopId != null && shopId > 0) {
                    if (csm != null && csm.equals(shopId) && !Objects.equals(src, shopId)) {
                        crossInflowAmount = crossInflowAmount.add(tot);
                        inflowOrders += count;
                    } else if (src != null && src.equals(shopId) && !Objects.equals(csm, shopId)) {
                        crossOutflowAmount = crossOutflowAmount.add(tot);
                        outflowOrders += count;
                    }
                } else {
                    crossInflowAmount = crossInflowAmount.add(tot);
                    inflowOrders += count;
                }

                Map<String, Object> item = new HashMap<>(row);
                if (shopId != null && shopId > 0) {
                    if (csm != null && csm.equals(shopId)) {
                        item.put("type", "INFLOW_RECEIVABLE"); // 应收
                    } else if (src != null && src.equals(shopId)) {
                        item.put("type", "OUTFLOW_PAYABLE"); // 应付
                    }
                }
                partnerBreakdown.add(item);
            }
        }

        BigDecimal netSettlement = crossInflowAmount.subtract(crossOutflowAmount);

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("shopId", shopId);
        summary.put("startDate", startDate);
        summary.put("endDate", endDate);
        summary.put("crossInflowAmount", crossInflowAmount);
        summary.put("crossOutflowAmount", crossOutflowAmount);
        summary.put("netSettlementAmount", netSettlement);
        summary.put("inflowOrderCount", inflowOrders);
        summary.put("outflowOrderCount", outflowOrders);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("summary", summary);
        result.put("breakdown", partnerBreakdown);
        return result;
    }
}
