package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_ticket")
public class KdsTicket {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Long station_id;

    private String screen_tag;

    private Integer order_id;

    private String order_no;

    private Integer detail_id;

    /** 0待制作 1制作中 2已完成 3已退菜 */
    private Integer item_status;

    /** 0待抓串 1已抓串（skewer_gate=1 时烤制屏仅展示=1） */
    private Integer skewer_picked;

    private Date skewer_picked_at;

    private Integer rush_flag;

    /** 加菜标记 0/1 */
    private Integer add_dish_flag;

    /** 超时标记 0/1 */
    private Integer overdue_flag;

    private Date overdue_at;

    private Date rush_at;

    private Integer order_number_snapshot;

    private Integer archived;

    /** 出餐屏已确认传菜数量（分批传菜，达到明细数量后 archived=1） */
    private Integer served_quantity;

    /** 已配菜数量（分批配菜，进入待制作池） */
    private Integer prep_quantity;

    /** 已制作完成数量（分批制作，进入待传菜池） */
    private Integer cooked_quantity;

    /** KDS V2 明细级单调版本；与收银端 local_order_lines.local_revision 对齐。 */
    private Long row_version;

    /** KDS V2 订单级单调版本；与收银端 local_orders.local_revision 对齐。 */
    private Long order_revision;

    private String void_reason;

    private Date created_at;

    private Date accepted_at;

    private Date done_at;

    private Date updated_at;
}
