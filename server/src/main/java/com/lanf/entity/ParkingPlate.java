package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

/**
 * 车牌信息实体
 */
@Data
@TableName("t_parking_plate")
public class ParkingPlate {
    /**
     * 主键ID
     */
    @TableId(type = IdType.AUTO)
    private Long id;

    /**
     * 完整车牌号
     */
    private String plate_number;

    /**
     * 车牌类型 1-燃油车 2-新能源车
     */
    private Integer plate_type;

    /**
     * 关联用户ID
     */
    private Long user_id;

    /**
     * 车牌省份
     */
    private String province;

    /**
     * 是否默认车牌 0-否 1-是
     */
    private Integer is_default;

    /**
     * 创建时间
     */
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime create_time;

    /**
     * 更新时间
     */
    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime update_time;

    /**
     * 是否删除 0-未删 1-已删
     */
    @TableLogic
    private Integer is_delete;
}