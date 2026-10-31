package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 统一业务命令账本
 */
@Data
@TableName("t_kds_v2_command")
public class KdsV2Command {
    
    @TableId(type = IdType.AUTO)
    private Long id;
    
    private Integer shop_id;
    
    /** 三端统一命令ID */
    private String command_id;
    
    /** 云端鉴权身份 */
    private String actor_id;
    
    /** 操作人类型 */
    private String actor_type;
    
    /** 命令类型 */
    private String command_type;
    
    /** 请求指纹，防重 */
    private String request_fingerprint;
    
    /** 协议版本 */
    private String request_schema_version;
    
    /** APPLIED / REJECTED */
    private String status;
    
    /** 稳定终态结果 (JSON) */
    private String result_json;
    
    private Date created_at;
    
    private Date updated_at;

    private Date applied_at;
}
