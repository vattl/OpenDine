package com.lanf.ai.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * AI配餐待确认订单草稿实体，对应 t_order_draft
 */
@Data
@TableName("t_order_draft")
public class OrderDraft {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String draft_id;

    private String plan_id;

    private String session_id;

    private Integer shop_id;

    private String table_number;

    private String openid;

    private String menu_version;

    /** 最终应付金额(分) */
    private Integer price_total_fen;

    /** 锁定快照商品列表JSON */
    private String items_snapshot_json;

    /** PENDING, PASSED, PRICE_CHANGED, OUT_OF_STOCK, EXPIRED */
    private String validation_status;

    private String idempotency_key;

    private String formal_order_no;

    private Date expires_at;

    private Date created_at;

    private Date updated_at;
}
