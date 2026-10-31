package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.ShopMemberWallet;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.math.BigDecimal;
import java.util.List;

public interface ShopMemberWalletMapper extends BaseMapper<ShopMemberWallet> {

    @Select("SELECT * FROM t_shop_member_wallet WHERE user_id = #{userId} AND shop_id = #{shopId} LIMIT 1")
    ShopMemberWallet selectByUserAndShop(@Param("userId") Integer userId, @Param("shopId") Integer shopId);

    @Select("SELECT * FROM t_shop_member_wallet WHERE user_id = #{userId} AND (principal_balance > 0 OR gift_balance > 0)")
    List<ShopMemberWallet> selectWalletsWithBalance(@Param("userId") Integer userId);

    @Select("SELECT IFNULL(SUM(principal_balance + gift_balance), 0) FROM t_shop_member_wallet WHERE shop_id = #{shopId}")
    BigDecimal sumBalanceByShop(@Param("shopId") Integer shopId);
}
