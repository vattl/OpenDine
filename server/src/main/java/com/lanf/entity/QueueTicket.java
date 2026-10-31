package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.util.Date;

/**
 * 排队取号记录，对应 t_queue_ticket。
 */
@Data
@TableName("t_queue_ticket")
public class QueueTicket {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String ticket_no;

    private String openid;

    private String mobile;

    private Integer party_size;

    private String dine_type;

    private String remark;

    private Integer shop_id;

    /**
     * waiting/calling/seated/cancelled/expired
     */
    private String status;

    private Date created_at;

    private Date updated_at;
}
