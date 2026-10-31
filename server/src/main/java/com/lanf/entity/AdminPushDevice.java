package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** Mobile admin device registered for vendor push delivery. */
@TableName("t_admin_push_device")
@Data
public class AdminPushDevice {

    @TableId(type = IdType.AUTO)
    private Long id;
    private Integer admin_id;
    private Integer shop_id;
    private String device_token;
    private String platform;
    private String channel;
    private String app_version;
    private String device_model;
    private Integer enabled;
    private Date last_registered_at;
    private Date created_at;
    private Date updated_at;
}
