package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 菜品库存变动流水日志实体，对应 t_dish_stock_log
 */
@Data
@TableName("t_dish_stock_log")
public class DishStockLog {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Integer dish_id;

    private String dish_name;

    private String order_no;

    private Integer detail_id;

    /**
     * 变动类型：
     * CREATE_ORDER(下单扣减), ADD_DISH(加菜扣减), CANCEL_ORDER(取消回退),
     * REFUND_RESTORE(退菜回退), REFUND_NO_RESTORE(退菜损耗), REFUND_OUT_OF_STOCK(缺货估清),
     * ADMIN_MANUAL(后台调库), KDS_LACK(KDS缺货/退菜)
     */
    private String change_type;

    /**
     * 变动数量 (+加 / -减 / 0不变)
     */
    private Integer delta;

    private Integer stock_before;

    private Integer stock_after;

    private String operator_id;

    private String remark;

    private Date created_at;
}
