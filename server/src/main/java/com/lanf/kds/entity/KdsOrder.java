package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_order")
public class KdsOrder {

    @TableId(type = IdType.INPUT)
    private Integer order_id;

    private Integer shop_id;

    private String order_no;

    /** 10/20/30/40/90 */
    private Integer kds_order_status;

    private Integer revision;

    private Date created_at;

    private Date updated_at;
}
