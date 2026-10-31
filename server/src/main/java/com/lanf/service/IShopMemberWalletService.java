package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.ShopMemberWallet;

import java.math.BigDecimal;
import java.util.Map;

/**
 * 门店会员钱包与跨店储值清算服务
 */
public interface IShopMemberWalletService extends IService<ShopMemberWallet> {

    String CONFIG_KEY_CROSS_SHOP_BALANCE = "member_balance_cross_shop_enabled";

    /**
     * 指定门店是否支持跨店使用会员余额（默认 true）
     */
    boolean isCrossShopBalanceEnabled(Integer shopId);

    /**
     * 设置门店是否允许跨店使用会员余额
     */
    void setCrossShopBalanceEnabled(int shopId, boolean enabled);

    /**
     * 查询指定用户在某门店的可用余额（本金+赠送金）
     */
    BigDecimal getAvailableBalanceForShop(Integer userId, Integer shopId);

    /**
     * 会员充值时增加门店会员钱包余额
     */
    void addBalance(Integer userId, Integer shopId, BigDecimal principal, BigDecimal gift);

    /**
     * 后台人工扣减指定门店会员钱包余额
     */
    boolean deductBalance(Integer userId, Integer shopId, BigDecimal amount);

    /**
     * 结账消费时扣减门店钱包余额；若发生跨店扣减，自动记录跨店清算明细
     * @return true 若扣减成功
     */
    boolean deductAndClearBalance(Integer userId, Integer consumeShopId, BigDecimal principal, BigDecimal gift, String orderNo);

    /**
     * 查询跨店储值清算汇总报表
     */
    Map<String, Object> getCrossShopClearingReport(Integer shopId, String startDate, String endDate);
}
