package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.io.Serializable;
import java.util.Date;

/**
 * 微信订阅消息场景与模板配置
 */
@Data
@TableName("t_subscribe_scene_template")
public class SubscribeSceneTemplate implements Serializable {

    @TableId(type = IdType.AUTO)
    private Integer id;

    /** 场景编码：ORDER_PICKUP, ORDER_STATUS, COUPON_EXPIRING 等 */
    private String scene_code;

    /** 微信模板ID */
    private String template_id;

    /** 模板标题 */
    private String title;

    /** 建议唤起节点：SUBMIT_ORDER, PAY_SUCCESS 等 */
    private String trigger_point;

    /** 是否启用：0禁用 1启用 */
    private Integer is_active;

    /** 参数映射配置JSON */
    private String param_mapping_json;

    /** 场景说明 */
    private String remark;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date created_at;

    @JsonSerialize(using = CustomDateTimeSerializer.class)
    private Date updated_at;
}
