package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.io.Serializable;
import java.util.Date;

/**
 * 桌号实体
 */
@TableName("t_table")
@Data
public class Table implements Serializable {

    private Integer id; // 编号

    private String number; // 桌号

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date open_time; // 创建日期

    private String qrcode; // 二维码地址

    private Integer status;

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date out_time; // 下单时间

    private Double amount;

    /** 当前关联订单号（开台/下单时写入，结账/清台时清空） */
    private String order_no;

    /** 门店 ID（连锁），对应 t_table.shop_id */
    private Integer shop_id;

    /** 区域编码（大厅散座 hall、特色包厢 box、露天外摆 patio 等） */
    private String area_code;

    /** 区域名称（如：大厅散座、特色包厢） */
    private String area_name;

}
