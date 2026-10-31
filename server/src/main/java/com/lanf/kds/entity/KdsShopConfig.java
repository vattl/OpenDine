package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_shop_config")
public class KdsShopConfig {

    @TableId(type = IdType.INPUT)
    private Integer shop_id;

    /** print_only | kds_only | both */
    private String kds_mode;

    private Integer sync_legacy_rece;

    /** 1=厨显整单完成（40）时自动置 order_receiving=off_order（清台） */
    private Integer auto_off_order_on_kds_done;

    /** 1=待传菜划单后打印飞鹅传菜单；0=不打印 */
    private Integer serve_print_enabled;

    private Integer auto_push_on_create;

    /** 1 先抓串再分流烤制屏；0 下单直推烤制屏 */
    private Integer skewer_gate;

    private String default_screen_tag;

    private Integer sla_minutes;

    private Integer archive_hours;

    private Integer lack_sets_sold_out;

    /** 1=合并相同菜品（跨订单汇总，美团默认开） */
    private Integer merge_same_dish;

    /** 1=堂食与打包内嵌同一行；0=堂/打包/外卖拆行（晚高峰防风干） */
    private Integer pack_inline_merge;

    /** 1=套餐子菜与散点同菜合并；0=套餐菜独立成行 */
    private Integer combo_merge;

    /** 1=启用待配菜环节（默认开启）；0=关闭待配菜环节（直接进入待制作） */
    private Integer enable_prep_workflow;

    /** KDS 门店极简登录 PIN 码（默认 123456） */
    private String kds_pin;

    private Date updated_at;
}
