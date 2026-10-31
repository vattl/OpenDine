package com.lanf.kds.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.annotation.JsonIgnore;
import lombok.Data;

import java.util.Date;
import java.util.List;

@Data
@TableName("t_kds_device")
public class KdsDevice {

    @TableId(type = IdType.AUTO)
    private Long id;

    private Integer shop_id;

    private Long station_id;

    private String screen_tag;

    private String device_code;

    private String device_name;

    private String device_token;

    /** SHA-256 of the bearer token. Raw tokens are never persisted after V009. */
    @JsonIgnore
    private String token_hash;

    private Date token_expires_at;

    private Date token_revoked_at;

    private String workflows_json;

    private Date last_heartbeat_at;

    private Integer enabled;

    private Date created_at;

    private Date updated_at;

    /** 非表字段：统一工作流看板设备负责的流程 prep/cook/serve */
    @TableField(exist = false)
    private List<String> workflows;

    /** 非表字段：设备可见烤制岗（meat_grill/veg_grill/seafood_special）；空=未配置（默认三岗全选） */
    @TableField(exist = false)
    private List<String> screen_tags;
}
