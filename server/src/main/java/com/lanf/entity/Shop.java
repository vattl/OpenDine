package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 门店，对应 t_shop
 */
@Data
@TableName("t_shop")
public class Shop {
    private Integer id;
    private String name;
    private String code;
    private String address;
    private String contact_phone;
    private String open_time;
    private String close_time;
    /** 每日结算截止时间（HH:mm），营业日统计窗口=[open_time, 次日 settle_time)；为空回退 close_time，再空回退 04:00 */
    private String settle_time;
    private Integer status;
    /** 列表排序，越小越靠前（需执行 chain_store 补丁后才有列） */
    private Integer sort_order;
    /** C 端是否接待下单：1 营业 0 休息（迁移见 db_migration_shop_ordering_flags.sql） */
    @TableField("ordering_open")
    private Integer ordering_open;
    /** C 端评价展示：1 开 0 关 */
    @TableField("ordering_review")
    private Integer ordering_review;
    /** 关门强制交班：1开 0关（迁移见 db_migration_shop_settle_flow.sql） */
    @TableField("shift_required")
    private Integer shift_required;
    /** 关门强制日结：1开 0关 */
    @TableField("settle_required")
    private Integer settle_required;
    private String remark;
    private java.math.BigDecimal latitude;
    private java.math.BigDecimal longitude;
    /** API input/output metadata only; persisted coordinates are always GCJ-02. */
    @TableField(exist = false)
    private String coordinate_type = "gcj02";
    /** 区域ID（P3） */
    private Integer region_id;
    private Date created_at;
    private Date updated_at;

    /** 微信个人收款码解码后的跳转串（如 wxp://），用于短时中转页重定向 */
    @TableField("offline_collect_wechat_payload")
    private String offline_collect_wechat_payload;
    /** 支付宝收款码解码后的跳转串 */
    @TableField("offline_collect_alipay_payload")
    private String offline_collect_alipay_payload;
    @TableField("offline_collect_wechat_image_path")
    private String offline_collect_wechat_image_path;
    @TableField("offline_collect_alipay_image_path")
    private String offline_collect_alipay_image_path;
}
