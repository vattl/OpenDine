package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

@Data
@TableName("t_kds_station_category")
public class KdsStationCategory {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long station_id;

    private String cid;

    private Date created_at;
}
