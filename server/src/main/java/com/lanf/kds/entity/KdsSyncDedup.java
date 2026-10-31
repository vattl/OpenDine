package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_sync_dedup")
public class KdsSyncDedup {

    @TableId(type = IdType.INPUT)
    private String client_id;

    private Integer shop_id;

    private Date created_at;
}
