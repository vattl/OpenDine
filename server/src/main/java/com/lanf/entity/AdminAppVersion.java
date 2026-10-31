package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/** Published client/admin application version policy across iOS, Android, and Windows. */
@TableName("t_admin_app_version")
@Data
public class AdminAppVersion {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String platform;
    private String channel;
    private String latest;
    private Integer version_code;
    private String min_supported;
    private Integer force_update;
    private String package_type;
    private String install_mode;
    private Long file_size;
    private String sha256;
    private String gray_shop_ids;
    private String release_notes;
    private String download_url;
    private Integer enabled;
    private Date created_at;
    private Date updated_at;
}
