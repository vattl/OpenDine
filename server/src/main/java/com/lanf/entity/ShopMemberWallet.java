package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.Date;

/**
 * 门店会员钱包，用于单店与连锁共存架构下的门店资金分账
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_shop_member_wallet")
public class ShopMemberWallet {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer user_id;

    private Integer shop_id;

    private BigDecimal principal_balance;

    private BigDecimal gift_balance;

    private BigDecimal total_recharge_principal;

    private BigDecimal total_recharge_gift;

    private Date created_at;

    private Date updated_at;
}
