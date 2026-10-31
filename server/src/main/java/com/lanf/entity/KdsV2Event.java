package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 统一持久化事件流
 */
@Data
@TableName("t_kds_v2_event")
public class KdsV2Event {
    
    @TableId(type = IdType.AUTO)
    private Long id;
    
    private Integer shop_id;
    
    /** 自增事件序列 */
    private Long event_seq;
    
    /** 事件唯一ID */
    private String event_id;
    
    /** 关联的命令ID */
    private String command_id;
    
    /** Schema version */
    private String schema_version;
    
    /** 受影响的业务实体ID */
    private String entity_id;
    
    /** 业务提交后的revision */
    private Integer business_revision;
    
    /** 完整变化载荷 */
    private String event_json;
    
    private Date created_at;
}
